# Remove the no-op `ggplot2::labs("")` call from MaAsLin2's association plots.
#
# This is the same defect already patched out of the vendored alpha_diversity.R,
# but here it lives inside the MaAsLin2 package (1.22.0), in
# maaslin2_association_plots(), so there is no script to vendor:
#
#   Error: <ggplot2::labels> object is invalid: - every label must be named.
#
# ggplot2 4.x builds labels as an S7 object whose validator rejects unnamed
# labels. MaAsLin2 reaches the call on the first *continuous* metadata variable
# -- the categorical boxplots all render first, so the run dies partway through
# the association plots, after the results tables are already written.
#
# Patching the shared install under lab_storage is not an option: it is live and
# used by everything else on the cluster, so the fix is applied in memory here.
#
# It patches MaAsLin2, not ggplot2, deliberately. The call site is fully
# qualified as `ggplot2::labs("")`, so shadowing `labs` on the search path never
# sees it, and the binding would have to be replaced inside ggplot2's own
# namespace -- which also puts the wrapper in front of ggplot2's internals.
# update_labels() calls labs() itself, and going through any wrapper breaks it
# with "Error in !defaults(labels, p@labels) : invalid argument type", whatever
# the wrapper does with the arguments. Rewriting the one MaAsLin2 function
# leaves ggplot2 untouched.
#
# Dropping the call cannot lose a label: with no named argument it contributes
# nothing, and under ggplot2 3.x it was silently ignored, which is why it
# survived upstream. The plots are unchanged.
#
# Source this before calling Maaslin2(). Delete this file once MaAsLin2 drops
# the call or the pinned R stack moves.

local({
    loadNamespace("Maaslin2")

    target <- "maaslin2_association_plots"
    original <- get(target, envir = asNamespace("Maaslin2"))

    source_text <- paste(deparse(original, width.cutoff = 500L), collapse = "\n")

    # drop the term, whether it is followed by another `+` term or ends the
    # expression
    patched_text <- sub("ggplot2::labs\\(\"\"\\)\\s*\\+\\s*", "", source_text)
    if (identical(patched_text, source_text))
        patched_text <- sub("\\s*\\+\\s*ggplot2::labs\\(\"\"\\)", "", source_text)

    if (identical(patched_text, source_text))
        stop("ggplot2_labs_shim: no ggplot2::labs(\"\") call found in Maaslin2:::",
             target, " -- MaAsLin2 ", utils::packageVersion("Maaslin2"),
             " may have fixed it; check whether this shim is still needed.")

    patched <- eval(parse(text = patched_text))
    environment(patched) <- asNamespace("Maaslin2")

    utils::assignInNamespace(target, patched, ns = "Maaslin2")
})
