test_that("resource registry exposes versioned defaults", {
    resources <- SpaMTPdbResources(default_only = TRUE)
    expect_true(all(c("resource", "version", "rdata_path") %in% names(resources)))
    expect_true("chem_props" %in% resources$resource)
    expect_identical(SpaMTPdbVersion(), "3.0.7")
})

test_that("local staged resources are loaded and checked", {
    path <- tempfile("spamtpdb-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    fixture <- data.frame(ramp_id = "RAMP_C_000000001", monoisotop_mass = 100)
    saveRDS(fixture, file.path(path, "chem_props.rds"))
    observed <- SpaMTPdbResource("chem_props", local_dir = path, offline = TRUE)
    expect_identical(observed, fixture)
})

test_that("metadata lookup does not download data", {
    metadata <- SpaMTPdbResource("pathway", metadata = TRUE)
    expect_identical(metadata$version, "3.0.7")
    expect_identical(metadata$category, "core")
})

test_that("SMILES features remain an independent structure resource", {
    metadata <- SpaMTPdbResource("smiles_features", metadata = TRUE)
    expect_identical(metadata$category, "structure")
    expect_false(metadata$default)
    expect_identical(metadata$r_data_class, "data.frame")
})

test_that("every resource records an external download location", {
    manifest <- SpaMTPdbResources()
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
    expect_false(any(duplicated(manifest$file_name)))
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
        SpaMTPdbResource("chem_props", local_dir = empty, offline = TRUE),
        "offline = TRUE"
    )
})

test_that("unknown resources are rejected", {
    expect_error(SpaMTPdbResource("not_a_resource"), "Unknown SpaMTPdb resource")
    expect_error(SpaMTPdbResources(version = "0.0.0"), "unavailable")
})
