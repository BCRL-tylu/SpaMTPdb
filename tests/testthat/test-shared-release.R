sharedReleaseHelpers <- function() {
    environment <- new.env(parent = baseenv())
    sys.source(system.file("scripts", "shared-release-utils.R", package = "SpaMTPdb"),
        envir = environment)
    environment
}

sharedReleaseFixture <- function(path) {
    dir.create(path)
    dbDir <- file.path(path, "db")
    nativeDir <- file.path(path, "native")
    dir.create(dbDir)
    dir.create(nativeDir)
    saveRDS(data.frame(value = 1:3), file.path(dbDir, "table.rds"))
    # Synthetic serialization fixture for the publication layer; no biology asserted.
    saveRDS(list(synthetic = TRUE), file.path(nativeDir, "experiment_spe.rds"))
    h <- sharedReleaseHelpers()
    database <- h$releaseFileRows(file.path(dbDir, "table.rds"))
    database$resource <- "table"
    database$version <- "3.0.7"
    database$r_data_class <- "data.frame"
    database$source_url <- "https://zenodo.org/records/22045311"
    source <- data.frame(resource = "experiment", version = "1.0.0",
        file_name = "legacy.rds", r_data_class = "Seurat", bytes = 20,
        md5 = strrep("a", 32L), source_url = "https://zenodo.org/records/17246900")
    native <- h$releaseFileRows(file.path(nativeDir, "experiment_spe.rds"))
    native$resource <- "experiment"
    native$version <- "1.1.0"
    native$r_data_class <- "SpatialExperiment"
    native$source_version <- source$version
    native$source_file <- source$file_name
    native$source_bytes <- source$bytes
    native$source_md5 <- source$md5
    native$source_url <- source$source_url
    config <- list(base_record_id = "22045311", concept_record_id = "22045310",
        base_version = "3.0.7", collection_version = "2026.09", title = "Shared resources",
        license = "cc-by-4.0", creators = list(list(name = "Causer, Andrew")),
        database_source = list(title = "Base database"), related_identifiers = list())
    list(h = h, database = database, dbDir = dbDir, native = native, nativeDir = nativeDir,
        registry = source, config = config, sources = list(list(
            doi = "10.5281/zenodo.17246900", record_url = source$source_url,
            license = list(id = "cc-by-4.0"), creators = list(list(name = "Causer, Andrew")))))
}

test_that("shared staging preserves ownership, resource versions and source files", {
    skip_if_not_installed("jsonlite")
    path <- tempfile("shared-release-")
    f <- sharedReleaseFixture(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    original <- tools::md5sum(c(f$database$local_path, f$native$local_path))
    release <- f$h$prepareSharedRelease(f$database, f$dbDir, f$native, f$nativeDir,
        f$registry, f$sources, f$config, file.path(path, "output"))
    expect_identical(release$manifest$owner_package, c("SpaMTPdb", "SpaMTPData"))
    expect_identical(release$manifest$hub, c("AnnotationHub", "ExperimentHub"))
    expect_identical(release$manifest$resource_version, c("3.0.7", "1.1.0"))
    expect_equal(nrow(release$plan), 7L)
    public <- utils::read.csv(file.path(path, "output", "resource_manifest.csv"))
    expect_false("local_path" %in% names(public))
    expect_false(any(c("upload-plan.csv", "release-config.json",
        "zenodo-metadata.draft.json") %in% release$plan$file_name))
    expect_identical(tools::md5sum(names(original)), original)
    expect_error(f$h$prepareSharedRelease(f$database, f$dbDir, f$native, f$nativeDir,
        f$registry, f$sources, f$config, file.path(path, "output")), "not empty")
})

test_that("staging rejects corruption, wrong provenance and incomplete replacement sets", {
    path <- tempfile("shared-release-")
    f <- sharedReleaseFixture(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    build <- function(native = f$native, database = f$database) {
        f$h$buildSharedManifest(database, f$dbDir, native, f$nativeDir, f$registry)
    }
    bad <- f$native
    bad$source_md5 <- strrep("b", 32L)
    expect_error(build(bad), "provenance")
    bad <- f$native
    bad$resource <- "wrong"
    expect_error(build(bad), "every historical")
    bad <- f$native
    bad$file_name <- "../experiment_spe.rds"
    expect_error(build(bad), "unsafe")
    bad <- f$native
    bad$file_name <- f$database$file_name
    expect_error(build(bad), "duplicate")
    saveRDS("changed", f$native$local_path)
    expect_error(build(), "MD5")
})

test_that("remote validation refuses unknown or changed files without deleting them", {
    h <- sharedReleaseHelpers()
    expected <- data.frame(file_name = c("one.rds", "two.rds"), bytes = c(10, 20),
        md5 = c(strrep("a", 32L), strrep("b", 32L)))
    record <- list(files = list(list(filename = "one.rds", filesize = 10,
        checksum = paste0("md5:", expected$md5[1L]))))
    expect_identical(h$releaseCheckRemote(expected, record), "two.rds")
    expect_error(h$releaseCheckRemote(expected, record, complete = TRUE), "missing")
    record$files[[1L]]$filename <- "unknown.rds"
    expect_error(h$releaseCheckRemote(expected, record), "unplanned")
    record$files[[1L]]$filename <- "one.rds"
    record$files[[1L]]$checksum <- expected$md5[2L]
    expect_error(h$releaseCheckRemote(expected, record), "nothing was overwritten")
})

test_that("uploads resume the same draft and never publish or replace existing data", {
    path <- tempfile("shared-release-")
    f <- sharedReleaseFixture(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    plan <- rbind(f$database[, c("file_name", "local_path", "bytes", "md5")],
        f$native[, c("file_name", "local_path", "bytes", "md5")])
    remoteFile <- function(row) list(key = row$file_name, size = row$bytes,
        checksum = paste0("md5:", row$md5))
    draft <- list(id = 999, conceptrecid = "22045310", submitted = FALSE,
        state = "unsubmitted", links = list(bucket = "https://zenodo.org/api/files/fixture"),
        files = list(remoteFile(plan[1L, ])), metadata = list(version = "3.0.7",
            title = "Base database"))
    metadata <- list(metadata = list(title = f$config$title,
        version = "2026.09", creators = f$config$creators))
    calls <- character()
    uploaded <- character()
    api <- function(path, method, body) {
        calls <<- c(calls, paste(method, path))
        if (method == "PUT") draft$metadata <<- body$metadata
        draft
    }
    upload <- function(bucket, row) {
        uploaded <<- c(uploaded, row$file_name)
        draft$files <<- c(draft$files, list(remoteFile(row)))
    }
    f$h$releaseUpload(plan, f$config, metadata, draft, api, upload)
    expect_identical(uploaded, "experiment_spe.rds")
    expect_false(any(grepl("POST|DELETE|actions", calls)))
    expect_false(draft$submitted)
    uploaded <- character()
    f$h$releaseUpload(plan, f$config, metadata, draft, api, upload)
    expect_length(uploaded, 0L)
    calls <- character()
    draft$submitted <- TRUE
    expect_error(f$h$releaseUpload(plan, f$config, metadata, draft, api, upload), "published")
    expect_length(calls, 0L)
    draft$submitted <- FALSE
    draft$conceptrecid <- "other"
    expect_error(f$h$releaseUpload(plan, f$config, metadata, draft, api, upload), "family")
    expect_length(calls, 0L)
})

test_that("credentials cannot be sent to arbitrary URLs", {
    h <- sharedReleaseHelpers()
    host <- "https://zenodo.org"
    expect_identical(h$releaseSafeUrl(paste0(host, "/api/files/abc"), host, "/api/files/"),
        paste0(host, "/api/files/abc"))
    expect_error(h$releaseSafeUrl("https://zenodo.org.evil.invalid/api/files/x",
        host, "/api/files/"), "Unsafe")
    expect_error(h$releaseSafeUrl("https://zenodo.org/api/files/x?access_token=x",
        host, "/api/files/"), "Unsafe")
})
