test_that("resource registry exposes versioned defaults", {
    resources <- spaMTPdbResources(default_only = TRUE)
    expect_true(all(c("resource", "version", "rdata_path") %in% names(resources)))
    expect_true("chem_props" %in% resources$resource)
    expect_identical(spaMTPdbVersion(), "3.0.7")
})

test_that("local staged resources are loaded and checked", {
    path <- tempfile("spamtpdb-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    fixture <- data.frame(ramp_id = "RAMP_C_000000001", monoisotop_mass = 100)
    saveRDS(fixture, file.path(path, "chem_props.rds"))
    observed <- spaMTPdbResource("chem_props", local_dir = path, offline = TRUE,
                                verify = FALSE)
    expect_identical(observed, fixture)
})

test_that("metadata lookup does not download data", {
    metadata <- spaMTPdbResource("pathway", metadata = TRUE)
    expect_identical(metadata$version, "3.0.7")
    expect_identical(metadata$category, "core")
})

test_that("SMILES features remain an independent structure resource", {
    metadata <- spaMTPdbResource("smiles_features", metadata = TRUE)
    expect_identical(metadata$category, "structure")
    expect_false(metadata$default)
    expect_identical(metadata$r_data_class, "data.frame")
})

test_that("every resource records an external download location", {
    manifest <- spaMTPdbResources()
    required <- c(
        "file_name", "location_prefix", "rdata_path", "dispatch_class",
        "bytes", "md5"
    )
    expect_true(all(required %in% names(manifest)))

    ## Bioconductor does not host these files, so no resource may point at the
    ## Hub bucket and every download URL must be absolute.
    expect_false(any(grepl("^s3://", manifest$location_prefix)))
    urls <- paste0(manifest$location_prefix, manifest$rdata_path)
    expect_true(all(grepl("^https://", urls)))

    expect_true(all(nzchar(manifest$file_name)))
    expect_false(any(duplicated(paste(manifest$version, manifest$file_name))))
    expect_true(all(manifest$bytes > 0))
    expect_true(all(grepl("^[0-9a-f]{32}$", manifest$md5)))
})

test_that("cached files are rejected when size or checksum disagree", {
    path <- tempfile("spamtpdb-", fileext = ".rds")
    on.exit(unlink(path), add = TRUE)
    saveRDS(seq_len(10L), path)

    row <- data.frame(
        bytes = file.info(path)$size,
        md5 = unname(tools::md5sum(path)),
        stringsAsFactors = FALSE
    )
    expect_true(.spamtpdb_file_valid(path, row))

    row$md5 <- strrep("0", 32L)
    expect_false(.spamtpdb_file_valid(path, row))

    row$md5 <- unname(tools::md5sum(path))
    row$bytes <- row$bytes + 1
    expect_false(.spamtpdb_file_valid(path, row))

    expect_false(.spamtpdb_file_valid(tempfile("absent-"), row))
})

test_that("offline lookups do not fall back to the network", {
    empty <- tempfile("spamtpdb-empty-")
    dir.create(empty)
    on.exit(unlink(empty, recursive = TRUE), add = TRUE)
    expect_error(
        spaMTPdbResource("chem_props", local_dir = empty, offline = TRUE,
                         cache_dir = file.path(empty, "cache")),
        "offline = TRUE"
    )
})

test_that("unknown resources are rejected", {
    expect_error(spaMTPdbResource("not_a_resource"), "Unknown SpaMTPdb resource")
    expect_error(spaMTPdbResources(version = "0.0.0"), "unavailable")
})

test_that("verified URL cache can be reused offline before querying AnnotationHub", {
    path <- tempfile("spamtpdb-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    fixture <- data.frame(ramp_id = "demo", monoisotop_mass = 100)
    filename <- file.path(path, "chem_props.rds")
    saveRDS(fixture, filename)
    row <- spaMTPdbResource("chem_props", metadata = TRUE)
    row$bytes <- file.info(filename)$size
    row$md5 <- unname(tools::md5sum(filename))
    row$location_prefix <- paste0("file://", normalizePath(path), "/")
    row$rdata_path <- basename(filename)
    cache <- file.path(path, "cache")
    .spamtpdb_download(row, cache, retries = 1L)
    local_mocked_bindings(.spamtpdb_manifest = function() row)
    expect_identical(spaMTPdbResource("chem_props", local_dir = file.path(path, "empty"),
        cache_dir = cache, offline = TRUE), fixture)
    saveRDS("corrupt", file.path(cache, row$version, row$file_name))
    expect_error(spaMTPdbResource("chem_props", local_dir = file.path(path, "empty"),
        cache_dir = cache, offline = TRUE), "offline = TRUE")
})

test_that("local files cannot silently impersonate official resource snapshots", {
    path <- tempfile("spamtpdb-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    fixture <- data.frame(ramp_id = "demo")
    saveRDS(fixture, file.path(path, "chem_props.rds"))
    expect_error(spaMTPdbResource("chem_props", local_dir = path, offline = TRUE), "MD5")
    expect_identical(spaMTPdbResource("chem_props", local_dir = path, offline = TRUE,
        verify = FALSE), fixture)
    saveRDS(42, file.path(path, "chem_props.rds"))
    expect_error(spaMTPdbResource("chem_props", local_dir = path, offline = TRUE,
        verify = FALSE), "expected data.frame")
    expect_error(spaMTPdbResource(character()), "one non-empty name")
    expect_error(spaMTPdbResource("chem_props", verify = NA), "TRUE or FALSE")
})

test_that("bundle defaults are resolved from the requested version", {
    registry <- spaMTPdbResources()[1:2, ]
    registry$version <- c("3.0.7", "3.0.8")
    local_mocked_bindings(.spamtpdb_manifest = function() registry)
    result <- spaMTPdbBundle(version = "3.0.7", metadata = TRUE)
    expect_named(result, registry$resource[1])
    expect_identical(result[[1]]$version, "3.0.7")
})

test_that("all exported functions follow camelCase", {
    expect_true(all(grepl("^[a-z][A-Za-z0-9]*$", getNamespaceExports("SpaMTPdb"))))
})
