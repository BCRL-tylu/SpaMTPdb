#!/usr/bin/env Rscript

## Stage the SpaMTPdb resource files and regenerate inst/extdata/resource_manifest.csv.
##
## Usage:
##   Rscript inst/scripts/stage_resources.R [source_root] [output_root] [version] [record_id]
##
## source_root  Checkout of the SpaMTP software package holding the original
##              data/*.rda objects. Only consulted when a staged .rds file is
##              missing, so a completed staging directory can be re-described
##              without the original sources.
## output_root  Directory holding <version>/<resource>.rds. Default ../SpaMTPdb-resources.
## version      Resource version. Default 3.0.7.
## record_id    Zenodo record ID hosting this version's files. Defaults to the
##              SPAMTPDB_ZENODO_RECORD environment variable.
##
## Resource files are hosted on Zenodo, not in the Bioconductor Hub bucket, so
## the manifest records the exact download URL, byte size and MD5 checksum used
## to verify each cached file.

args <- commandArgs(trailingOnly = TRUE)
source_root <- if (length(args) >= 1L) args[[1L]] else "../SpaMTP"
output_root <- if (length(args) >= 2L) args[[2L]] else "../SpaMTPdb-resources"
version <- if (length(args) >= 3L) args[[3L]] else "3.0.7"
record_id <- if (length(args) >= 4L) {
    args[[4L]]
} else {
    Sys.getenv("SPAMTPDB_ZENODO_RECORD", "")
}

if (!nzchar(record_id)) {
    stop(
        "No Zenodo record ID supplied. Pass it as the fourth argument or set ",
        "SPAMTPDB_ZENODO_RECORD. Run inst/scripts/zenodo_upload.R first to ",
        "create the deposition.",
        call. = FALSE
    )
}
record_id <- sub("^.*/", "", trimws(as.character(record_id)[1L]))
if (!grepl("^[0-9]+$", record_id)) {
    stop("Zenodo record ID must be numeric, got '", record_id, "'.", call. = FALSE)
}

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_path <- sub("^--file=", "", script_arg)
package_root <- normalizePath(
    file.path(dirname(script_path), "..", ".."), mustWork = TRUE
)
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

## Describing a resource needs its class and dimensions. Loading all sixteen
## objects costs well over a gigabyte of memory, so reuse the recorded values
## whenever the staged file is byte-identical to the one already described.
manifest_path <- file.path(
    package_root, "inst", "manifest", "resource_manifest.csv"
)
dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
previous <- if (file.exists(manifest_path)) {
    utils::read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
} else {
    NULL
}

describe <- function(value) {
    dimensions <- dim(value)
    list(
        r_data_class = paste(class(value), collapse = "/"),
        rows = if (is.null(dimensions)) length(value) else dimensions[[1L]],
        columns = if (length(dimensions) >= 2L) dimensions[[2L]] else NA_integer_,
        object_bytes = as.numeric(object.size(value))
    )
}

for (field in c("r_data_class", "rows", "columns", "object_bytes", "bytes", "md5")) {
    resources[[field]] <- rep(NA, nrow(resources))
}

for (i in seq_len(nrow(resources))) {
    resource <- resources$resource[[i]]
    target <- file.path(version_dir, paste0(resource, ".rds"))

    if (!file.exists(target)) {
        if (is.na(resources$source_file[[i]])) {
            stop(
                "Missing precomputed resource: ", target,
                ". Run precompute_smiles_features.R first.",
                call. = FALSE
            )
        }
        source_file <- file.path(
            normalizePath(source_root, mustWork = TRUE), "data",
            resources$source_file[[i]]
        )
        if (!file.exists(source_file)) {
            stop("Missing source file: ", source_file, call. = FALSE)
        }
        environment <- new.env(parent = emptyenv())
        loaded <- load(source_file, envir = environment)
        object_name <- resources$source_object[[i]]
        if (!object_name %in% loaded) {
            stop("Object '", object_name, "' is absent from ", source_file,
                 call. = FALSE)
        }
        saveRDS(environment[[object_name]], target, compress = "xz", version = 3L)
        message("Staged ", resource, " -> ", target)
    }

    bytes <- file.info(target)$size
    md5 <- unname(tools::md5sum(target))

    cached <- if (!is.null(previous)) {
        previous[
            previous$resource == resource &
                as.character(previous$version) == version &
                as.character(previous$md5) == md5,
            , drop = FALSE
        ]
    } else {
        previous
    }

    if (!is.null(cached) && nrow(cached) == 1L &&
        !is.na(cached$r_data_class[[1L]])) {
        description <- list(
            r_data_class = cached$r_data_class[[1L]],
            rows = cached$rows[[1L]],
            columns = cached$columns[[1L]],
            object_bytes = cached$object_bytes[[1L]]
        )
    } else {
        message("Describing ", resource, " (reading ", target, ")")
        description <- describe(readRDS(target))
    }

    resources$r_data_class[[i]] <- description$r_data_class
    resources$rows[[i]] <- description$rows
    resources$columns[[i]] <- description$columns
    resources$object_bytes[[i]] <- description$object_bytes
    resources$bytes[[i]] <- bytes
    resources$md5[[i]] <- md5
}

## Zenodo serves file content from the REST API. Splitting the download URL into
## a prefix and a path keeps the Hub metadata columns meaningful while still
## concatenating to the exact URL the package downloads.
resources$version <- version
resources$title <- paste0("SpaMTPdb_", resources$resource, "_", version)
resources$file_name <- paste0(resources$resource, ".rds")
resources$location_prefix <- paste0(
    "https://zenodo.org/api/records/", record_id, "/files/"
)
resources$rdata_path <- paste0(resources$file_name, "/content")
resources$source_url <- paste0("https://zenodo.org/records/", record_id)
resources$dispatch_class <- "Rds"

resources <- resources[c(
    "resource", "version", "category", "default", "title", "file_name",
    "location_prefix", "rdata_path", "source_url", "source_file",
    "source_object", "r_data_class", "dispatch_class", "rows", "columns",
    "bytes", "object_bytes", "md5"
)]
utils::write.csv(resources, manifest_path, row.names = FALSE, na = "")
message(
    "Wrote ", manifest_path, " for Zenodo record ", record_id,
    " (", nrow(resources), " resources, ",
    format(sum(resources$bytes) / 1e6, digits = 4), " MB)."
)
