#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
source_root <- if (length(args) >= 1L) args[[1L]] else "../SpaMTP"
output_root <- if (length(args) >= 2L) args[[2L]] else "../SpaMTPdb-resources"
version <- if (length(args) >= 3L) args[[3L]] else "3.0.7"

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_path <- sub("^--file=", "", script_arg)
package_root <- normalizePath(
    file.path(dirname(script_path), "..", ".."), mustWork = TRUE
)
source_root <- normalizePath(source_root, mustWork = TRUE)
version_dir <- file.path(normalizePath(output_root, mustWork = FALSE), version)
dir.create(version_dir, recursive = TRUE, showWarnings = FALSE)

resources <- data.frame(
    resource = c(
        "chem_props", "source_df", "analyte", "analytehaspathway", "pathway",
        "ramp_db_metadata", "ramp_hmdb", "ramp_kegg", "ramp_reactome",
        "ramp_wikipathway", "hmdb_db", "chebi_db", "lipidmaps_db", "gnps_db",
        "filtered_fmp10", "smiles_features"
    ),
    source_file = c(
        "chem_props.rda", "source_df.rda", "analyte.rda", "analytehaspathway.rda",
        "pathway.rda", "ramp_db_metadata.rda", "RAMP_hmdb.rda", "RAMP_kegg.rda",
        "RAMP_Reactome.rda", "RAMP_wikipathway.rda", "HMDB_db.rda", "Chebi_db.rda",
        "Lipidmaps_db.rda", "GNPS_db.rda", "filtered_fmp10.rda", NA_character_
    ),
    source_object = c(
        "chem_props", "source_df", "analyte", "analytehaspathway", "pathway",
        "ramp_db_metadata", "RAMP_hmdb", "RAMP_kegg", "RAMP_Reactome",
        "RAMP_wikipathway", "HMDB_db", "Chebi_db", "Lipidmaps_db", "GNPS_db",
        "filtered_fmp10", "smiles_features"
    ),
    category = c(
        rep("core", 6L), rep("topology", 4L), rep("legacy", 5L), "structure"
    ),
    default = c(rep(TRUE, 10L), rep(FALSE, 6L)),
    stringsAsFactors = FALSE
)
resources$r_data_class <- rep(NA_character_, nrow(resources))
resources$rows <- rep(NA_integer_, nrow(resources))
resources$columns <- rep(NA_integer_, nrow(resources))
resources$serialized_bytes <- rep(NA_real_, nrow(resources))
resources$object_bytes <- rep(NA_real_, nrow(resources))
resources$md5 <- rep(NA_character_, nrow(resources))

for (i in seq_len(nrow(resources))) {
    target <- file.path(version_dir, paste0(resources$resource[[i]], ".rds"))
    if (resources$resource[[i]] == "smiles_features") {
        if (!file.exists(target)) {
            stop(
                "Missing precomputed structure resource: ", target,
                ". Run precompute_smiles_features.R first."
            )
        }
        value <- readRDS(target)
    } else {
        source_file <- file.path(source_root, "data", resources$source_file[[i]])
        if (!file.exists(source_file)) stop("Missing source file: ", source_file)
        environment <- new.env(parent = emptyenv())
        loaded <- load(source_file, envir = environment)
        object_name <- resources$source_object[[i]]
        if (!object_name %in% loaded) {
            stop("Object '", object_name, "' is absent from ", source_file)
        }
        value <- environment[[object_name]]
        if (!file.exists(target)) {
            saveRDS(value, target, compress = "xz", version = 3L)
        }
    }
    dimensions <- dim(value)
    resources$r_data_class[[i]] <- paste(class(value), collapse = "/")
    resources$rows[[i]] <- if (is.null(dimensions)) length(value) else dimensions[[1L]]
    resources$columns[[i]] <- if (length(dimensions) >= 2L) dimensions[[2L]] else NA_integer_
    resources$serialized_bytes[[i]] <- file.info(target)$size
    resources$object_bytes[[i]] <- as.numeric(object.size(value))
    resources$md5[[i]] <- unname(tools::md5sum(target))
    message("Staged ", resources$resource[[i]], " -> ", target)
}

resources$version <- version
resources$rdata_path <- paste0(
    "SpaMTPdb/", version, "/", resources$resource, ".rds"
)
resources$title <- paste0("SpaMTPdb_", resources$resource, "_", version)
resources <- resources[c(
    "resource", "version", "category", "default", "title", "rdata_path",
    "source_file", "source_object", "r_data_class", "rows", "columns",
    "serialized_bytes", "object_bytes", "md5"
)]
utils::write.csv(
    resources,
    file.path(package_root, "inst", "extdata", "resource_manifest.csv"),
    row.names = FALSE,
    na = ""
)
