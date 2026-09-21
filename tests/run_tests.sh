#!/bin/bash
# Integration test suite. The version under test is nextflow.config's
# manifest.version, printed in the summary below.
#
# Run from anywhere: bash tests/run_tests.sh
# Under SLURM:       sbatch tests/submit_tests.sh
# Requires: the hutlab module environment loaded, and Java 21 on PATH.
#
# This is the only test suite. The nf-test cases that used to sit alongside it
# were removed in the v0.0.4 cleanup: they asserted a four-process pipeline,
# loaded params files that were not in the repo, and so had not run in a long
# time. What CI can check without the tool stack is checked by
# bin/make_diagrams.py --check instead; everything here needs real software,
# real databases and a cluster.
#
# Covers every workflow except 16s, in both library layouts:
#
#   workflow   single-end            paired-end
#   ---------- --------------------- ---------------------------
#   mgx        QC + tax + func       QC + tax + func, and a
#                                    --run_qc false merge_pairs run
#   mtx        QC(3 dbs) + tax       QC(3 dbs) + tax
#   mgx_mtx    both halves, tax      both halves, mapped, + func
#   assembly   full MAG/SGB          full MAG/SGB
#   vis/stats  folder input, no layout of their own
#
# plus the version log and the two input guards.
#
# The read-based runs are independent, so their nextflow drivers run in
# parallel; each gets its own work directory. Checks run after all of them
# have finished.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_BASE="${REPO_ROOT}/tests/results"
WORK_BASE="${REPO_ROOT}/tests/work"
NF="/n/lab_storage/huttenhower_lab/tools/nextflow/24.10.4/bin/nextflow"
# The profile carries the databases and the tool modules; conf/harvard_rc.yaml
# is a template of commented-out settings and is deliberately not passed, so
# each test states its own input and nothing is inherited silently.
PROFILE="-profile harvard_rc"
COMMON="--run_viral_profiling false --run_strain_profiling false"
# Chaining vis/stats is exercised deliberately by tests 3 and 7; the other runs
# turn it off so a report failure cannot mask the stage they are testing.
NO_REPORTS="--run_vis false --run_stats false"
# The vis/stats fixture lives outside the repo; regenerate it with
# `python ~/biobakery_vis_stats_test/make_fixture.py --output input`.
FIXTURE="${VIS_STATS_FIXTURE:-${HOME}/biobakery_vis_stats_test/input}"
# The assembly fixture is simulated from two real genomes, because the bundled
# reads cannot produce a MAG; regenerate it with
# `python3 ~/biobakery_assembly_test/make_fixture.py --output input_pe`
# (add --single for input_se).
ASM_FIXTURE="${ASSEMBLY_FIXTURE:-${HOME}/biobakery_assembly_test}"
# Reported in the summary, so a log says which release it came from.
VERSION="$(sed -n "s/^ *version *= *'\(.*\)'.*/\1/p" "${REPO_ROOT}/nextflow.config")"

mkdir -p "${RESULTS_BASE}" "${WORK_BASE}"

# Two-sample metadata for the chained stats run in test 3. Two samples is below
# what most of the stats analyses need, so that test asserts the report is
# produced, not that every section has content.
printf 'sample\tgroup\nFG00004_S26\tcase\nFG00005_S50_L001\tcontrol\n' \
    > "${RESULTS_BASE}/mgx_metadata.tsv"

pass=0; fail=0

# Run one nextflow invocation. Named log, named work directory, and a
# .status file so the parallel runs can be judged after the fact.
nf_run() {
    local name="$1"; shift
    local out="${RESULTS_BASE}/${name}"
    local launch="${WORK_BASE}/${name}_launch"
    # the .status file goes too: a leftover from a previous run reads as this
    # run's result while this one is still going
    rm -rf "${out}" "${WORK_BASE}/${name}" "${launch}"
    rm -f  "${RESULTS_BASE}/${name}.status"
    mkdir -p "${launch}"
    # Each driver launches from its own directory: concurrent runs sharing one
    # launch directory share .nextflow/ -- the history file and the cache -- and
    # tread on each other.
    (
        cd "${launch}" || exit 1
        "${NF}" run "${REPO_ROOT}/main.nf" ${PROFILE} \
            --outdir "${out}" \
            -work-dir "${WORK_BASE}/${name}" \
            "$@"
    ) > "${RESULTS_BASE}/${name}.log" 2>&1
    echo "$?" > "${RESULTS_BASE}/${name}.status"
}

# Did the run exit 0?
check_run() {
    local name="$1"
    local status
    status="$(cat "${RESULTS_BASE}/${name}.status" 2>/dev/null || echo missing)"
    if [ "${status}" = "0" ]; then
        echo "[PASS] ${name}: nextflow completed"
        ((pass++))
    else
        echo "[FAIL] ${name}: nextflow exited ${status}"
        grep -E "^ERROR|Caused by:|Command error:" -A3 "${RESULTS_BASE}/${name}.log" | head -20 >&2
        ((fail++))
    fi
}

# Are the named output patterns all present under the run's output folder?
check_files() {
    local name="$1"; shift
    local dir="${RESULTS_BASE}/${name}"
    local ok=true
    for p in "$@"; do
        if ! find "${dir}" -name "${p}" 2>/dev/null | grep -q .; then
            echo "  MISSING in ${name}: ${p}" >&2
            ok=false
        fi
    done
    if $ok; then
        echo "[PASS] ${name}: expected outputs present"
        ((pass++))
    else
        echo "[FAIL] ${name}: expected outputs missing"
        ((fail++))
    fi
}

note() { echo ""; echo "=== $* ==="; }

# ── The read-based runs, in parallel ─────────────────────────────────────────
note "Launching the read-based runs"

# 1. version log only — local executor, no SLURM jobs
nf_run test1_versionlog \
    --workflow mgx \
    --readsdir "${REPO_ROOT}/tests/data/single_end_rawfastq" \
    --paired_end false \
    --run_qc false --run_taxonomic_profiling false --run_functional_profiling false \
    ${COMMON} ${NO_REPORTS} --log_versions true &

# 2. mgx single-end, full stack: KneadData + MetaPhlAn + HUMAnN, and the
#    chained vis report with no metadata at all. --run_stats true without
#    metadata must skip with a warning rather than fail the run, which is the
#    other half of what this test checks.
nf_run test2_mgx_se \
    --workflow mgx \
    --readsdir "${REPO_ROOT}/tests/data/single_end_rawfastq" \
    --paired_end false \
    --run_stats true \
    ${COMMON} --log_versions true &

# 3. mgx paired-end, full stack, with metadata, so the chained vis report also
#    builds its metadata-driven figures. Chained stats is deliberately left off:
#    MaAsLin2, HAllA and the mantel test cannot fit anything on two samples, so
#    it is opt-in and covered standalone by test 12.
nf_run test3_mgx_pe \
    --workflow mgx \
    --readsdir "${REPO_ROOT}/tests/data/rawfastq" \
    --input_metadata "${RESULTS_BASE}/mgx_metadata.tsv" \
    ${COMMON} --log_versions true &

# 4. mgx paired-end with QC bypassed: exercises merge_pairs, since MetaPhlAn
#    takes one input file per sample and the raw pair is two.
nf_run test4_mgx_pe_noqc \
    --workflow mgx \
    --readsdir "${REPO_ROOT}/tests/data/rawfastq" \
    --run_qc false --run_functional_profiling false \
    ${COMMON} ${NO_REPORTS} --log_versions false &

# 5. mtx single-end — the metatranscriptome database set
nf_run test5_mtx_se \
    --workflow mtx \
    --readsdir "${REPO_ROOT}/tests/data/single_end_rawfastq" \
    --paired_end false \
    --run_functional_profiling false \
    ${COMMON} ${NO_REPORTS} --log_versions false &

# 6. mtx paired-end
nf_run test6_mtx_pe \
    --workflow mtx \
    --readsdir "${REPO_ROOT}/tests/data/rawfastq" \
    --run_functional_profiling false \
    ${COMMON} ${NO_REPORTS} --log_versions false &

wait

# mgx_mtx needs a second input folder, built from the same reads under
# different names. Stand-in RNA samples: the pairing is what is being tested,
# not the biology.
FIX="${RESULTS_BASE}/mgx_mtx_fixture"
rm -rf "${FIX}"; mkdir -p "${FIX}/mtx_pe" "${FIX}/mtx_se"
for r in 1 2; do
    cp "${REPO_ROOT}/tests/data/rawfastq/FG00004_S26_R${r}.fastq.gz" "${FIX}/mtx_pe/RNA_FG00004_S26_R${r}.fastq.gz"
done
cp "${REPO_ROOT}/tests/data/single_end_rawfastq/FG00004_S26_R1.fastq.gz" "${FIX}/mtx_se/RNA_FG00004_S26_R1.fastq.gz"
printf '#rna\tdna\nRNA_FG00004_S26\tFG00004_S26\n' > "${FIX}/mapping.tsv"

note "Launching mgx_mtx, assembly, vis and stats"

# 7. mgx_mtx paired-end, with a mapping file and functional profiling, so the
#    RNA/DNA relative expression ratio runs.
nf_run test7_mgx_mtx_pe \
    --workflow mgx_mtx \
    --input_metagenome "${REPO_ROOT}/tests/data/rawfastq" \
    --input_metatranscriptome "${FIX}/mtx_pe" \
    --input_mapping "${FIX}/mapping.tsv" \
    --run_stats false \
    ${COMMON} --log_versions false &

# 8. mgx_mtx single-end, no mapping file: each half is profiled on its own.
nf_run test8_mgx_mtx_se \
    --workflow mgx_mtx \
    --input_metagenome "${REPO_ROOT}/tests/data/single_end_rawfastq" \
    --input_metatranscriptome "${FIX}/mtx_se" \
    --paired_end false \
    --run_functional_profiling false \
    ${COMMON} ${NO_REPORTS} --log_versions false &

# 9./10. assembly, both layouts
nf_run test9_assembly_se \
    --workflow assembly \
    --readsdir "${REPO_ROOT}/tests/data/single_end_rawfastq" \
    --paired_end false \
    ${COMMON} ${NO_REPORTS} --log_versions false &

nf_run test10_assembly_pe \
    --workflow assembly \
    --readsdir "${REPO_ROOT}/tests/data/rawfastq" \
    ${COMMON} ${NO_REPORTS} --log_versions false &

# 11a./11b. assembly on the simulated fixture, which does produce MAGs
if [ -d "${ASM_FIXTURE}/input_pe" ]; then
    nf_run test13_assembly_mags_pe \
        --workflow assembly \
        --readsdir "${ASM_FIXTURE}/input_pe" \
        ${COMMON} ${NO_REPORTS} --log_versions false &
fi
if [ -d "${ASM_FIXTURE}/input_se" ]; then
    nf_run test14_assembly_mags_se \
        --workflow assembly \
        --readsdir "${ASM_FIXTURE}/input_se" \
        --paired_end false \
        ${COMMON} ${NO_REPORTS} --log_versions false &
fi

# 11./12. vis and stats, on the generated bioBakery-output fixture
if [ -d "${FIXTURE}" ]; then
    nf_run test11_vis \
        --workflow vis \
        --vis_input "${FIXTURE}" \
        --input_metadata "${FIXTURE}/metadata.tsv" \
        --project_name "vis test" &

    nf_run test12_stats \
        --workflow stats \
        --stats_input "${FIXTURE}" \
        --input_metadata "${FIXTURE}/metadata.tsv" \
        --project_name "stats test" \
        --stats_fixed_effects 'diagnosis,age' &
fi

wait

# ── Checks ───────────────────────────────────────────────────────────────────
note "Test 1: version log"
check_run   test1_versionlog
check_files test1_versionlog "pipeline_log.txt"

# The chained reports are asserted through the folder they are built from --
# outdir/report_input, in the bioBakery layout files.ShotGun expects -- not
# through the report itself. Two samples of a thousand reads cannot produce an
# ordination or a heatmap, so vis legitimately fails on this data; that failure
# is ignored by design (conf/base.config, withName '.*:REPORTING:.*') and the
# profiling run still completes. A report with content needs a real study.
note "Test 2: mgx single-end — KneadData + MetaPhlAn + HUMAnN + chained vis"
check_run   test2_mgx_se
check_files test2_mgx_se "*_kneaddata.log" "*_profile_*.tsv" "merged_metaphlan_profiles.tsv" \
                         "*_genefamilies_*.tsv" "*_pathabundance_*.tsv" "humann_feature_counts.tsv" \
                         "metaphlan_taxonomic_profiles.tsv" "kneaddata_read_count_table.tsv" \
                         "ecs_relab.tsv"

# Chained stats needs metadata, which this run is not given: it must be skipped
# with a warning, not fail the run and not silently produce a report.
if grep -q "Skipping the chained stats workflow" "${RESULTS_BASE}/test2_mgx_se.log" \
   && [ ! -d "${RESULTS_BASE}/test2_mgx_se/stats" ]; then
    echo "[PASS] test2_mgx_se: chained stats skipped without metadata"
    ((pass++))
else
    echo "[FAIL] test2_mgx_se: chained stats did not skip cleanly without metadata"
    ((fail++))
fi

note "Test 3: mgx paired-end — KneadData + MetaPhlAn + HUMAnN + chained vis"
check_run   test3_mgx_pe
check_files test3_mgx_pe "*_kneaddata_paired_1.fastq.gz" "*_profile_*.tsv" "merged_metaphlan_profiles.tsv" \
                         "*_genefamilies_*.tsv" "*_pathabundance_*.tsv" "humann_feature_counts.tsv" \
                         "kneaddata_read_count_table.tsv" "metaphlan_species_counts_table.tsv" \
                         "humann_read_and_species_count_table.tsv" \
                         "metaphlan_taxonomic_profiles.tsv" "pathabundance_relab.tsv"

note "Test 4: mgx paired-end with QC bypassed — merge_pairs"
check_run   test4_mgx_pe_noqc
check_files test4_mgx_pe_noqc "*_profile_*.tsv" "merged_metaphlan_profiles.tsv"
# Look for the merged file rather than for the process name: the progress table
# elides long names, and lists processes that never ran.
if find "${WORK_BASE}/test4_mgx_pe_noqc" -name "*_merged.fastq.gz" | grep -q .; then
    echo "[PASS] test4_mgx_pe_noqc: pairs were merged before profiling"
    ((pass++))
else
    echo "[FAIL] test4_mgx_pe_noqc: merge_pairs did not run"
    ((fail++))
fi

note "Test 5: mtx single-end"
check_run   test5_mtx_se
check_files test5_mtx_se "*_kneaddata.log" "*_profile_*.tsv" "merged_metaphlan_profiles.tsv"

note "Test 6: mtx paired-end"
check_run   test6_mtx_pe
check_files test6_mtx_pe "*_kneaddata.log" "*_profile_*.tsv" "merged_metaphlan_profiles.tsv"

# The metatranscriptome database set is the point of the mtx workflow: KneadData
# should have written contaminant files for the host genome, the host mRNA and
# the rRNA index, not just the host genome.
for t in test5_mtx_se test6_mtx_pe; do
    dbs=$(find "${WORK_BASE}/${t}" -name "*_contam*.fastq*" -printf "%f\n" 2>/dev/null \
          | sed -E 's/.*_kneaddata_(.*)_bowtie2_.*/\1/' | sort -u | wc -l)
    if [ "${dbs}" -ge 3 ]; then
        echo "[PASS] ${t}: KneadData used ${dbs} reference databases"
        ((pass++))
    else
        echo "[FAIL] ${t}: KneadData used ${dbs} reference database(s), expected 3"
        ((fail++))
    fi
done

note "Test 7: mgx_mtx paired-end, mapped, with the RNA/DNA ratio"
check_run   test7_mgx_mtx_pe
check_files test7_mgx_mtx_pe "whole_metagenome_shotgun" "whole_metatranscriptome_shotgun" \
                             "*_genefamilies_*.tsv" "*relative_expression*"
# With a mapping file the RNA samples borrow the DNA sample's taxonomic profile,
# so the metatranscriptome half must not have run MetaPhlAn of its own.
if [ -d "${RESULTS_BASE}/test7_mgx_mtx_pe/whole_metatranscriptome_shotgun/metaphlan" ]; then
    echo "[FAIL] test7_mgx_mtx_pe: TAX_MTX:metaphlan ran despite a mapping file"
    ((fail++))
else
    echo "[PASS] test7_mgx_mtx_pe: mapped run reuses the metagenome profiles"
    ((pass++))
fi
# The chained report stages the metagenome half at the root of its own folder.
check_files test7_mgx_mtx_pe "metaphlan_taxonomic_profiles.tsv"

note "Test 8: mgx_mtx single-end, unmapped"
check_run   test8_mgx_mtx_se
check_files test8_mgx_mtx_se "whole_metagenome_shotgun" "whole_metatranscriptome_shotgun"
# Without a mapping file each half is profiled on its own.
if [ -d "${RESULTS_BASE}/test8_mgx_mtx_se/whole_metatranscriptome_shotgun/metaphlan" ]; then
    echo "[PASS] test8_mgx_mtx_se: the metatranscriptome half was profiled on its own"
    ((pass++))
else
    echo "[FAIL] test8_mgx_mtx_se: TAX_MTX:metaphlan did not run without a mapping file"
    ((fail++))
fi

# The bundled reads are heavily host-dominated -- KneadData leaves on the order
# of a thousand reads per sample -- so MEGAHIT assembles no contigs and no MAGs
# are produced. These two tests therefore cover that every stage runs, in both
# layouts, and that the no-MAG path is carried through to a final profile.
# Binning, CheckM2, PhyloPhlAn and SGB clustering on real MAGs are covered by
# tests 13 and 14, on the simulated fixture.
note "Test 9: assembly single-end"
check_run   test9_assembly_se
check_files test9_assembly_se "*.final.contigs.fa" "*.contig_depths.txt" "*.abundance.tsv" \
                              "merged_quality_report.tsv" "phylophlan_out.tsv" "final_profile.tsv"

note "Test 10: assembly paired-end"
check_run   test10_assembly_pe
check_files test10_assembly_pe "*.final.contigs.fa" "*.contig_depths.txt" "*.abundance.tsv" \
                               "merged_quality_report.tsv" "phylophlan_out.tsv" "final_profile.tsv"

for t in test13_assembly_mags_pe test14_assembly_mags_se; do
    layout="paired-end"; [ "${t}" = "test14_assembly_mags_se" ] && layout="single-end"
    if [ ! -f "${RESULTS_BASE}/${t}.status" ]; then
        note "Test ${t}: SKIPPED — no assembly fixture at ${ASM_FIXTURE}"
        echo "  Regenerate it with: python3 ~/biobakery_assembly_test/make_fixture.py --output input_pe"
        continue
    fi
    note "Assembly on simulated reads (${layout}) — MAGs end to end"
    check_run   "${t}"
    check_files "${t}" "*.final.contigs.fa" "*.contig_depths.txt" "*.abundance.tsv" \
                       "merged_quality_report.tsv" "phylophlan_out.tsv" "SGB_info.tsv" \
                       "final_profile.tsv"

    # This is what the bundled reads cannot show: contigs, real bins, and a
    # profile with rows in it.
    bins=$(find "${RESULTS_BASE}/${t}/bins" -name "*.bin.[0-9]*.fa" -size +0c 2>/dev/null | wc -l)
    rows=$(tail -n +2 "${RESULTS_BASE}/${t}/final_profile.tsv" 2>/dev/null | grep -c . || true)
    if [ "${bins}" -ge 1 ] && [ "${rows}" -ge 1 ]; then
        echo "[PASS] ${t}: ${bins} MAG(s) binned, ${rows} row(s) in the final profile"
        ((pass++))
    else
        echo "[FAIL] ${t}: ${bins} MAG(s) binned, ${rows} row(s) in the final profile"
        ((fail++))
    fi
done

if [ -d "${FIXTURE}" ]; then
    note "Test 11: vis"
    check_run   test11_vis
    check_files test11_vis "mgx_report.html" "vis.zip"

    note "Test 12: stats"
    check_run   test12_stats
    check_files test12_stats "stats_report.html" "stats.zip" "maaslin2*"
else
    note "Tests 11-12: vis / stats SKIPPED — no fixture at ${FIXTURE}"
    echo "  Regenerate it with: python ~/biobakery_vis_stats_test/make_fixture.py --output input"
fi

# ── Guards, which fail fast and need no cluster ──────────────────────────────
note "Test 15: toggle guard — viral profiling without taxonomic profiling"
"${NF}" run "${REPO_ROOT}/main.nf" ${PROFILE} \
    --workflow mgx \
    --readsdir "${REPO_ROOT}/tests/data/single_end_rawfastq" \
    --paired_end false \
    --outdir "${RESULTS_BASE}/test15_guard_out" \
    --run_qc false --run_taxonomic_profiling false --run_functional_profiling false \
    --run_viral_profiling true --log_versions false \
    2>&1 | grep "ERROR" | head -2 > "${RESULTS_BASE}/test15_guard.log"

if grep -q "run_taxonomic_profiling = false, but these require it" "${RESULTS_BASE}/test15_guard.log"; then
    echo "[PASS] viral-without-taxonomic guard fires"
    ((pass++))
else
    echo "[FAIL] viral-without-taxonomic guard did NOT fire"
    ((fail++))
fi

note "Test 16: mgx_mtx guard — both input folders are required"
"${NF}" run "${REPO_ROOT}/main.nf" ${PROFILE} \
    --workflow mgx_mtx \
    --input_metagenome "${REPO_ROOT}/tests/data/rawfastq" \
    --outdir "${RESULTS_BASE}/test16_guard_out" --log_versions false \
    2>&1 | grep "ERROR" | head -3 > "${RESULTS_BASE}/test16_guard.log"

if grep -q "input_metatranscriptome" "${RESULTS_BASE}/test16_guard.log"; then
    echo "[PASS] mgx_mtx two-input guard fires"
    ((pass++))
else
    echo "[FAIL] mgx_mtx two-input guard did NOT fire"
    ((fail++))
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  biobakery-workflows-nextflow ${VERSION}"
echo "  Results: ${pass} passed, ${fail} failed"
echo "  Logs:    ${RESULTS_BASE}/"
echo "========================================"
[ "${fail}" -eq 0 ]
