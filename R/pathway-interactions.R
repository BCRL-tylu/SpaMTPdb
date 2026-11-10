.spamtpdb_interaction_repair_cache <- new.env(parent = emptyenv())

.spamtpdb_graph_fingerprint <- function(value) {
    # Provenance attached by a loader does not change the resource contents.
    attributes(value) <- attributes(value)[intersect(names(attributes(value)), "names")]
    digest::digest(value, algo = "sha256", serializeVersion = 2L)
}

.spamtpdb_apply_interaction_patch <- function(value, patch) {
    if (!identical(.spamtpdb_graph_fingerprint(value), patch$input_sha256)) {
        return(value)
    }
    for (i in seq_along(patch$pathways)) {
        fields <- patch$pathways[[i]]
        for (field in names(fields)) {
            fix <- fields[[field]]
            edge <- value[[i]][[field]][fix$rows, , drop = FALSE]
            edge$directed <- fix$directed
            edge$reaction_type <- fix$reaction_type
            edge$source_reaction_type <- fix$source_reaction_type
            rownames(edge) <- NULL
            value[[i]][[field]] <- edge
        }
    }
    attr(value, "spamtp_interaction_repair") <- patch$provenance
    value
}

.spamtpdb_repair_pathway_interactions <- function(value, resource, patch_dir = NULL) {
    if (!resource %in% c(
        "ramp_kegg",
        "ramp_reactome",
        "ramp_wikipathway",
        "ramp_hmdb"
    ) ||
        !is.list(value) || !is.null(attr(value, "spamtp_interaction_repair", exact = TRUE))) {
        return(value)
    }
    if (is.null(.spamtpdb_interaction_repair_cache[[resource]])) {
        path <- if (is.null(patch_dir)) {
            system.file("extdata", paste0(resource, "_interactions_v1.rds"), package = "SpaMTPdb")
        } else file.path(patch_dir, paste0(resource, "_interactions_v1.rds"))
        if (!nzchar(path)) stop("Cannot locate the pathway interaction correction resource.")
        .spamtpdb_interaction_repair_cache[[resource]] <- readRDS(path)
    }
    patch <- .spamtpdb_interaction_repair_cache[[resource]]
    .spamtpdb_apply_interaction_patch(value, patch)
}
