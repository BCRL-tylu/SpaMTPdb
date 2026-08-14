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
