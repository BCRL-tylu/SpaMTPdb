# Maintainer-only shared resource publication; not loaded by the R package.

releaseRequire <- function(condition, message) {
    if (!isTRUE(condition)) stop(message, call. = FALSE)
}

releaseReadCsv <- function(path) {
    utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

releaseRequireColumns <- function(x, columns) {
    releaseRequire(all(columns %in% names(x)),
        paste("Missing columns:", paste(setdiff(columns, names(x)), collapse = ", ")))
}

releaseCheckFiles <- function(plan) {
    releaseRequireColumns(plan, c("file_name", "local_path", "bytes", "md5"))
    releaseRequire(nrow(plan) > 0L && !anyNA(plan) &&
        !anyDuplicated(plan$file_name) &&
        all(grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", plan$file_name)),
        "Empty, duplicate or unsafe upload filename/entry.")
    releaseRequire(all(file.exists(plan$local_path)) &&
        all(!file.info(plan$local_path)$isdir), "An upload file is missing.")
    releaseRequire(all(file.info(plan$local_path)$size == plan$bytes) &&
        all(grepl("^[0-9a-f]{32}$", plan$md5)) &&
        identical(unname(tools::md5sum(plan$local_path)), plan$md5),
        "An upload file failed its size or MD5 check.")
    invisible(plan)
}

releaseFileRows <- function(paths) {
    paths <- normalizePath(paths, mustWork = TRUE)
    data.frame(file_name = basename(paths), local_path = paths,
        bytes = file.info(paths)$size, md5 = unname(tools::md5sum(paths)),
        stringsAsFactors = FALSE)
}

buildSharedManifest <- function(database, databaseDir, native, nativeDir, registry) {
    releaseRequireColumns(database, c("resource", "version", "file_name",
        "r_data_class", "bytes", "md5", "source_url"))
    releaseRequireColumns(native, c("resource", "version", "file_name",
        "r_data_class", "bytes", "md5", "source_version", "source_md5",
        "source_file", "source_bytes", "source_url"))
    releaseRequire(length(unique(native$version)) == 1L &&
        length(unique(native$source_version)) == 1L &&
        length(unique(database$version)) == 1L &&
        !anyDuplicated(native$resource) && !anyDuplicated(database$resource),
        "Select exactly one database and one native resource version.")
    source <- registry[registry$version == native$source_version[1L], , drop = FALSE]
    expected <- source$resource[source$r_data_class == "Seurat"]
    releaseRequire(setequal(native$resource, expected) && length(expected) > 0L,
        "The native release must cover every historical Seurat resource.")
    index <- match(native$resource, source$resource)
    releaseRequire(!anyNA(index) &&
        identical(native$source_md5, source$md5[index]) &&
        identical(native$source_file, source$file_name[index]) &&
        identical(native$source_url, source$source_url[index]) &&
        all(native$source_bytes == source$bytes[index]) &&
        all(native$r_data_class == "SpatialExperiment"),
        "Native provenance or container class disagrees with the published registry.")
    releaseRequire(utils::compareVersion(native$version[1L],
        native$source_version[1L]) > 0L, "Native resources need a new version.")
    convert <- function(x, directory, owner, hub) {
        data.frame(owner_package = owner, hub = hub, resource = x$resource,
            resource_version = x$version, file_name = x$file_name,
            r_data_class = x$r_data_class, bytes = x$bytes, md5 = x$md5,
            source_url = x$source_url,
            local_path = file.path(normalizePath(directory, mustWork = TRUE), x$file_name),
            stringsAsFactors = FALSE)
    }
    manifest <- rbind(convert(database, databaseDir, "SpaMTPdb", "AnnotationHub"),
        convert(native, nativeDir, "SpaMTPData", "ExperimentHub"))
    releaseCheckFiles(manifest)
    manifest
}

releaseRemoteFiles <- function(record) {
    if (!length(record$files)) return(data.frame(file_name = character(),
        bytes = numeric(), md5 = character(), stringsAsFactors = FALSE))
    do.call(rbind, lapply(record$files, function(x) {
        name <- if (is.null(x$key)) x$filename else x$key
        if (is.null(name)) name <- x$name
        bytes <- if (is.null(x$size)) x$filesize else x$size
        data.frame(file_name = as.character(name), bytes = as.numeric(bytes),
            md5 = sub("^md5:", "", as.character(x$checksum)), stringsAsFactors = FALSE)
    }))
}

releaseCheckRemote <- function(expected, record, complete = FALSE) {
    remote <- releaseRemoteFiles(record)
    releaseRequire(!anyNA(remote) && !anyDuplicated(remote$file_name),
        "Remote file list is malformed or duplicated.")
    index <- match(remote$file_name, expected$file_name)
    releaseRequire(!anyNA(index), "Remote draft contains unplanned files; nothing was deleted.")
    releaseRequire(all(remote$bytes == expected$bytes[index]) &&
        identical(remote$md5, expected$md5[index]),
        "A remote file differs from the plan; nothing was overwritten.")
    if (complete) releaseRequire(setequal(remote$file_name, expected$file_name),
        "The remote record is missing planned files.")
    setdiff(expected$file_name, remote$file_name)
}

releaseCheckDraft <- function(draft, config) {
    releaseRequire(length(draft$id) == 1L && grepl("^[0-9]+$", as.character(draft$id)),
        "Malformed draft identifier.")
    releaseRequire(!isTRUE(draft$submitted) && identical(draft$state, "unsubmitted"),
        "Refusing to write to a published record or an edit of published files.")
    releaseRequire(identical(as.character(draft$conceptrecid),
        as.character(config$concept_record_id)) &&
        as.character(draft$id) != as.character(config$base_record_id),
        "Draft does not belong to the configured version family.")
    invisible(draft)
}

releaseSafeUrl <- function(url, host, prefix) {
    releaseRequire(is.character(url) && length(url) == 1L && !is.na(url) &&
        startsWith(url, paste0(host, prefix)) &&
        !grepl("[?#[:space:]]", url), "Unsafe or unexpected Zenodo API URL.")
    url
}

releaseUpload <- function(plan, config, metadata, draft, api, upload) {
    # Validate the entire draft before changing metadata or uploading any file.
    releaseCheckFiles(plan)
    releaseCheckDraft(draft, config)
    missing <- releaseCheckRemote(plan, draft)
    existing <- draft$metadata$version
    releaseRequire(is.null(existing) || existing %in%
        c(config$base_version, config$collection_version),
        "Existing draft has a different release version; inspect it manually.")
    releaseRequire(is.null(draft$metadata$title) || draft$metadata$title %in%
        c(config$title, config$database_source$title),
        "Existing draft has a different title; inspect it manually.")
    path <- paste0("/api/deposit/depositions/", draft$id)
    api(path, "PUT", metadata)
    for (name in missing) {
        row <- plan[plan$file_name == name, , drop = FALSE]
        releaseCheckFiles(row)
        upload(draft$links$bucket, row)
    }
    final <- api(path, "GET", NULL)
    releaseCheckDraft(final, config)
    releaseCheckRemote(plan, final, complete = TRUE)
    releaseRequire(identical(final$metadata$title, metadata$metadata$title) &&
        identical(final$metadata$version, metadata$metadata$version) &&
        identical(vapply(final$metadata$creators, function(x) x$name, ""),
            vapply(metadata$metadata$creators, function(x) x$name, "")),
        "Remote metadata does not match the release draft.")
    invisible(final)
}

prepareSharedRelease <- function(database, databaseDir, native, nativeDir,
                                registry, sources, config, output) {
    manifest <- buildSharedManifest(database, databaseDir, native, nativeDir, registry)
    releaseRequire(all(database$source_url ==
        paste0("https://zenodo.org/records/", config$base_record_id)),
        "Database files must match the configured base record.")
    releaseRequire(length(config$creators) > 0L && nzchar(config$collection_version),
        "Collection version and creators are required.")
    sourceUrls <- vapply(sources, function(x) x$record_url, "")
    releaseRequire(!anyDuplicated(sourceUrls) &&
        setequal(sourceUrls, unique(native$source_url)) &&
        all(vapply(sources, function(x) length(x$creators) > 0L &&
            identical(x$license$id, config$license), TRUE)),
        "Source attribution is incomplete or source licences require separate review.")
    releaseRequire(!dir.exists(output) || !length(list.files(output, all.files = TRUE,
        no.. = TRUE)), "Output directory is not empty; use a fresh staging directory.")
    dir.create(output, recursive = TRUE, showWarnings = FALSE)
    output <- normalizePath(output, mustWork = TRUE)
    # Actual payload stays at its verified source paths; do not duplicate large RDS.
    public <- manifest[, names(manifest) != "local_path", drop = FALSE]
    utils::write.csv(public, file.path(output, "resource_manifest.csv"), row.names = FALSE)
    native <- native[, names(native) != "publication_status", drop = FALSE]
    utils::write.csv(native, file.path(output, "native_resource_manifest.csv"), row.names = FALSE)
    config$database_version <- as.character(unique(database$version))
    config$native_version <- as.character(unique(native$version))
    config$source_registry_version <- as.character(unique(native$source_version))
    jsonlite::write_json(config, file.path(output, "release-config.json"),
        pretty = TRUE, auto_unbox = TRUE)
    attribution <- list(database_source = config$database_source,
        experiment_sources = sources,
        changes = paste("Selected counts/data, annotations, centroids and paired transcriptomes",
            "were converted from Seurat to SpatialExperiment. Optical rasters, polygons,",
            "molecule coordinates, scaled matrices, graphs, reductions, commands and weights",
            "were omitted. Original data layers are not assumed to be log-normalized."))
    jsonlite::write_json(attribution, file.path(output, "source-attribution.json"),
        pretty = TRUE, auto_unbox = TRUE)
    description <- paste0(
        "<p>Shared SpaMTP resource collection, maintained through SpaMTPdb. ",
        "Annotation databases (version ", config$database_version, ") are accessed by SpaMTPdb; ",
        "native experimental resources (version ", config$native_version,
        ") are catalogued and read by SpaMTPData. The R packages do not bundle these files ",
        "and do not depend on each other at runtime.</p>",
        "<p>This collection extends the existing Zenodo version family. The original RaMP ",
        "snapshot and its identifiers are preserved. Database and experiment versions are ",
        "independent of the collection and R package versions.</p>",
        "<p>The native RDS are standalone SpatialExperiment objects; reading them requires ",
        "neither Seurat nor SpaMTP. Paired SPT transcriptomes are retained for DHB striatum ",
        "and human brain, without assuming pairing across independent experiments. ",
        "Original data layers retain their values and interpretation. Optical rasters, ",
        "polygons, molecule coordinates, scaled matrices, graphs, reductions, commands and ",
        "Seurat-specific weights are omitted. Historical WNN or polygon analyses are not ",
        "reproduced.</p><p>Source attribution and per-file versions/checksums are provided ",
        "in the accompanying manifests and source-attribution.json. Original data authors ",
        "remain credited separately from collection creators. Hub registration is a separate ",
        "step; availability of these files does not assert that Hub IDs have been assigned.</p>")
    metadata <- list(metadata = list(title = config$title, upload_type = "dataset",
        description = description, version = config$collection_version,
        creators = config$creators, access_right = "open", license = config$license,
        keywords = c("SpaMTP", "SpaMTPdb", "SpaMTPData", "Bioconductor",
            "SpatialExperiment", "mass spectrometry imaging", "metabolite annotation"),
        related_identifiers = c(config$related_identifiers,
            lapply(sources, function(x) list(identifier = x$doi, relation = "isDerivedFrom",
                scheme = "doi")))))
    jsonlite::write_json(metadata, file.path(output, "zenodo-metadata.draft.json"),
        pretty = TRUE, auto_unbox = TRUE)
    writeLines(c("# SpaMTP shared resource collection", "",
        paste("Collection version:", config$collection_version),
        paste("Database resource version:", config$database_version),
        paste("Native experimental resource version:", config$native_version), "",
        "SpaMTPdb provides annotation-database access; SpaMTPData provides experimental",
        "resource discovery and reading. Both use this shared file collection, while",
        "their registries and Bioconductor Hub metadata remain separate.", "",
        "resource_manifest.csv identifies the owning package, resource version, class,",
        "source URL, file size and MD5. native_resource_manifest.csv adds native",
        "dimensions, layers, selected coordinates, paired assays and source hashes.",
        "source-attribution.json preserves source creators, references and licences.",
        "MD5SUMS covers data files and these four descriptive files, not itself.", "",
        paste("The database files are unchanged from the original RaMP",
            config$database_version, "snapshot."),
        "The native files retain counts/data, feature and pixel annotations, centroids",
        "and explicitly paired transcriptomes. The existing data layers are not renamed",
        "logcounts or assumed to be log-normalized. Simulated datasets remain synthetic.",
        "Optical rasters, polygons, molecule payloads, scaled layers, graphs, reductions,",
        "commands and Seurat weight objects are omitted. This is not a full historical",
        "WNN or polygon-overlap reconstruction. Independent objects are not assumed paired.", "",
        "```r", "library(SpatialExperiment)",
        'spe <- readRDS("mouse_brain_dhb_striatum_spe.rds")',
        'SingleCellExperiment::altExp(spe, "SPT")',
        "SpatialExperiment::spatialCoords(spe)", "```", "",
        "Reading native RDS requires standard Bioconductor containers, not Seurat,",
        "SpaMTP or SpaMTPData. Preparation-time status in RDS provenance is historical,",
        "not a live hosting/registration indicator. Recipe hashes and software versions",
        "are recorded in each RDS; preparation recipes are shipped with SpaMTPData.", "",
        "Shared preparation verifies local file sizes and MD5 against their manifests.",
        "The native conversion recipe checks retained components against source archives.",
        "Scientific workflow validation and fresh public download checks are separate steps.", "",
        "Data are redistributed under the stated source licences; see source-attribution.json.",
        "Publication on Zenodo and ingestion into AnnotationHub/ExperimentHub are separate."),
        file.path(output, "README-resources.md"))
    documents <- file.path(output, c("resource_manifest.csv", "native_resource_manifest.csv",
        "source-attribution.json", "README-resources.md"))
    plan <- rbind(manifest[, c("file_name", "local_path", "bytes", "md5")],
        releaseFileRows(documents))
    writeLines(paste(plan$md5, plan$file_name, sep = "  "), file.path(output, "MD5SUMS"))
    plan <- rbind(plan, releaseFileRows(file.path(output, "MD5SUMS")))
    releaseCheckFiles(plan)
    utils::write.csv(plan, file.path(output, "upload-plan.csv"), row.names = FALSE)
    invisible(list(manifest = manifest, plan = plan, config = config, metadata = metadata))
}
