#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
spamtp_root <- if (length(args) >= 1L) args[[1L]] else "../SpaMTP"
resource_root <- if (length(args) >= 2L) args[[2L]] else "../SpaMTPdb-resources"
version <- if (length(args) >= 3L) args[[3L]] else "3.0.7"
workers <- if (length(args) >= 4L) as.integer(args[[4L]]) else 8L
chunk_size <- if (length(args) >= 5L) as.integer(args[[5L]]) else 10000L

if (is.na(workers) || workers < 1L) stop("workers must be positive")
if (is.na(chunk_size) || chunk_size < 1L) stop("chunk_size must be positive")

spamtp_root <- normalizePath(spamtp_root, mustWork = TRUE)
version_dir <- file.path(normalizePath(resource_root, mustWork = TRUE), version)
chem_file <- file.path(version_dir, "chem_props.rds")
target_file <- file.path(version_dir, "smiles_features.rds")
checkpoint_file <- file.path(version_dir, "smiles_features.partial.rds")
if (!file.exists(chem_file)) stop("Missing staged chem_props: ", chem_file)

source(file.path(spamtp_root, "R", "SMILESStructure.R"), local = .GlobalEnv)
chem_props <- readRDS(chem_file)
if (!"iso_smiles" %in% names(chem_props)) {
    stop("chem_props does not contain iso_smiles")
}
smiles <- unique(as.character(chem_props$iso_smiles))
smiles <- smiles[!is.na(smiles) & nzchar(smiles)]

parts <- list()
processed <- 0L
if (file.exists(checkpoint_file)) {
    checkpoint <- readRDS(checkpoint_file)
    if (identical(checkpoint$smiles, smiles) && is.list(checkpoint$parts)) {
        parts <- checkpoint$parts
        processed <- as.integer(checkpoint$processed)
        message("Resuming after ", processed, " of ", length(smiles), " structures")
    }
}

starts <- if (processed < length(smiles)) {
    seq.int(processed + 1L, length(smiles), by = chunk_size)
} else integer()
for (start in starts) {
    end <- min(length(smiles), start + chunk_size - 1L)
    part <- DeconvolveSMILES(
        smiles[start:end], backend = "native", strict = FALSE, workers = workers
    )
    parts[[length(parts) + 1L]] <- part
    processed <- end
    saveRDS(
        list(smiles = smiles, processed = processed, parts = parts),
        checkpoint_file,
        compress = "gzip",
        version = 3L
    )
    message("Parsed ", processed, " / ", length(smiles), " unique SMILES")
}

smiles_features <- do.call(rbind, parts)
rownames(smiles_features) <- NULL
stopifnot(nrow(smiles_features) == length(smiles))
saveRDS(smiles_features, target_file, compress = "xz", version = 3L)
if (file.exists(checkpoint_file)) file.remove(checkpoint_file)
message("Wrote ", target_file, " (", nrow(smiles_features), " rows)")
