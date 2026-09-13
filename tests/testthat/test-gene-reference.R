geneReferenceFixture <- function(path) {
    dir.create(path)
    value <- data.frame(hgnc_id = "HGNC:1", symbol = "SYNTHETIC", status = "Approved",
        prev_symbol = "OLD", alias_symbol = "ALIAS", entrez_id = "1",
        ensembl_gene_id = "ENSG0001", uniprot_ids = "U1")
    filename <- file.path(path, "reference.tsv")
    utils::write.table(value, filename, sep = "\t", row.names = FALSE, quote = TRUE)
    row <- spaMTPdbGeneReference(metadata = TRUE)
    row$file_name <- "reference.tsv"
    row$bytes <- file.info(filename)$size
    row$md5 <- unname(tools::md5sum(filename))
    list(value = value, file = filename, row = row)
}

test_that("HGNC versions are independent of the unchanged RaMP registry", {
    row <- spaMTPdbGeneReference(metadata = TRUE)
    expect_identical(row$version, "2026.7.7")
    expect_identical(row$organism, "Homo sapiens")
    expect_true(grepl("quarterly/tsv/", row$location_prefix))
    expect_true(grepl("2026-07-07", row$rdata_path))
    expect_true(grepl("^[0-9a-f]{32}$", row$md5))
    expect_identical(spaMTPdbVersion(), "3.0.7")
    expect_error(spaMTPdbGeneReference(version = "3.0.7", metadata = TRUE), "unavailable")
})

test_that("gene references validate local bytes and preserve their provenance", {
    path <- tempfile("gene-reference-")
    f <- geneReferenceFixture(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    local_mocked_bindings(.spamtpdb_gene_manifest = function() f$row)
    out <- spaMTPdbGeneReference(local_dir = path, offline = TRUE)
    expect_equal(out$symbol, "SYNTHETIC")
    expect_type(out$entrez_id, "character")
    expect_identical(attr(out, "spamtp_gene_reference")$md5, f$row$md5)
    expect_identical(attr(out, "spamtp_gene_reference")$provider, "SpaMTPdb")
    writeLines("changed", f$file)
    expect_error(spaMTPdbGeneReference(local_dir = path, offline = TRUE), "MD5")
})

test_that("gene references use a verified cache offline and never query a live symbol service", {
    path <- tempfile("gene-reference-")
    f <- geneReferenceFixture(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    f$row$location_prefix <- paste0("file://", normalizePath(path), "/")
    f$row$rdata_path <- basename(f$file)
    local_mocked_bindings(.spamtpdb_gene_manifest = function() f$row)
    cache <- file.path(path, "cache")
    .spamtpdb_download(f$row, cache, retries = 1L)
    expect_equal(spaMTPdbGeneReference(local_dir = file.path(path, "absent"),
        cache_dir = cache, offline = TRUE)$symbol, "SYNTHETIC")
    expect_error(spaMTPdbGeneReference(local_dir = file.path(path, "absent"),
        cache_dir = file.path(path, "empty"), offline = TRUE), "offline = TRUE")
})
