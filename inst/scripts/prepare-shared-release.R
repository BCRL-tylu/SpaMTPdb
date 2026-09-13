#!/usr/bin/env Rscript

# Prepare a shared, versioned Zenodo payload without uploading or changing registries.
# Usage: prepare-shared-release.R DB_FILES NATIVE_FILES SPAMTPDATA_ROOT OUTPUT COLLECTION_VERSION
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop(paste("Usage: prepare-shared-release.R",
    "DB_FILES NATIVE_FILES SPAMTPDATA_ROOT OUTPUT COLLECTION_VERSION"), call. = FALSE)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Install jsonlite.")
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(),
    value = TRUE)[1L]), mustWork = TRUE)
root <- normalizePath(file.path(dirname(script), "..", ".."), mustWork = TRUE)
source(file.path(dirname(script), "shared-release-utils.R"))
config <- jsonlite::read_json(file.path(root, "inst", "manifest", "shared_record.json"))
config$collection_version <- args[[5L]]
releaseRequire(grepl("^[0-9][A-Za-z0-9._-]*$", config$collection_version),
    "Use a filesystem-safe collection version, e.g. 2026.09.")
database <- releaseReadCsv(file.path(root, "inst", "manifest", "resource_manifest.csv"))
database <- database[database$version == config$base_version, , drop = FALSE]
native <- releaseReadCsv(file.path(args[[2L]], "native_resource_manifest.csv"))
registry <- releaseReadCsv(file.path(args[[3L]], "inst", "manifest", "resource_manifest.csv"))
sources <- jsonlite::read_json(file.path(args[[3L]], "inst", "manifest", "native_source_records.json"))
result <- prepareSharedRelease(database, args[[1L]], native, args[[2L]], registry,
    sources, config, args[[4L]])
message("Prepared ", nrow(result$manifest), " resources and ",
    nrow(result$plan) - nrow(result$manifest), " supplements in ", normalizePath(args[[4L]]),
    ". Nothing uploaded; published registries unchanged.")
