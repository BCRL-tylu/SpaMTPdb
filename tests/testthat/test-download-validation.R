test_that("download arguments are validated before lookup or cache creation", {
    invalid <- list(NULL, numeric(), c(1, 2), "3", TRUE, NA_real_,
                    NaN, Inf, -Inf, 0, -1, 1 + 1i)
    cache <- tempfile("spamtpdb-invalid-")
    for (value in invalid) {
        expect_error(.spamtpdb_download(NULL, cache, timeout = value), "timeout")
        expect_error(.spamtpdb_download(NULL, cache, retries = value), "retries")
        expect_error(spaMTPdbResource("chem_props", metadata = TRUE,
                                     timeout = value), "timeout")
        expect_error(spaMTPdbGeneReference(metadata = TRUE,
                                          retries = value), "retries")
    }
    expect_false(dir.exists(cache))
    for (value in list(1.5, .Machine$integer.max + 1)) {
        expect_error(spaMTPdbResource("chem_props", metadata = TRUE,
                                     retries = value), "whole number")
    }
    expect_error(spaMTPdbGeneReference(metadata = TRUE, timeout = "60"),
                 "timeout")
    expect_no_error(spaMTPdbResource("chem_props", metadata = TRUE,
                                    timeout = 1.5, retries = 2))
    expect_no_error(spaMTPdbGeneReference(metadata = TRUE,
                                         timeout = 60L, retries = 1L))
})

test_that("invalid manifest sizes are rejected without coercion warnings", {
    path <- tempfile("spamtpdb-size-")
    on.exit(unlink(path), add = TRUE)
    writeLines("fixture", path)
    row <- list(bytes = file.info(path)$size,
                md5 = unname(tools::md5sum(path)))
    expect_true(.spamtpdb_file_valid(path, row))
    for (value in list(NULL, numeric(), "invalid", as.character(row$bytes),
                       c(1, 2), TRUE, NA_real_, Inf, 1 + 1i)) {
        row$bytes <- value
        expect_warning(valid <- .spamtpdb_file_valid(path, row), NA)
        expect_false(valid)
    }
})

test_that("downloads retry checksum failures and restore the caller's timeout", {
    path <- tempfile("spamtpdb-retry-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    source <- file.path(path, "fixture.rds")
    saveRDS(data.frame(value = 1), source)
    row <- spaMTPdbResource("chem_props", metadata = TRUE)
    row$bytes <- file.info(source)$size
    row$md5 <- unname(tools::md5sum(source))
    state <- new.env(parent = emptyenv())
    state$calls <- 0L
    state$timeouts <- numeric()
    local_mocked_bindings(download.file = function(url, destfile, ...) {
        state$calls <- state$calls + 1L
        state$timeouts <- c(state$timeouts, getOption("timeout"))
        if (state$calls == 1L) writeLines("corrupt", destfile)
        else file.copy(source, destfile)
        0L
    })
    old <- options(timeout = 2400)
    on.exit(options(old), add = TRUE)
    cache <- file.path(path, "cache")
    downloaded <- .spamtpdb_download(row, cache, timeout = 60, retries = 2)
    expect_identical(readRDS(downloaded), readRDS(source))
    expect_identical(state$calls, 2L)
    expect_equal(state$timeouts, c(2400, 2400))
    expect_equal(getOption("timeout"), 2400)
    expect_length(list.files(cache, pattern = "[.]part-", recursive = TRUE), 0L)
    expect_identical(.spamtpdb_download(row, cache), downloaded)
    expect_identical(state$calls, 2L)
})

test_that("failed retries retain the error and remove partial downloads", {
    cache <- tempfile("spamtpdb-failed-")
    on.exit(unlink(cache, recursive = TRUE), add = TRUE)
    state <- new.env(parent = emptyenv())
    state$calls <- 0L
    local_mocked_bindings(download.file = function(url, destfile, ...) {
        state$calls <- state$calls + 1L
        writeLines("partial", destfile)
        stop("temporary download failure")
    })
    old <- options(timeout = 60)
    on.exit(options(old), add = TRUE)
    row <- spaMTPdbResource("chem_props", metadata = TRUE)
    expect_error(.spamtpdb_download(row, cache, timeout = 120, retries = 2),
                 "after 2 attempt.*temporary download failure")
    expect_identical(state$calls, 2L)
    expect_equal(getOption("timeout"), 60)
    expect_length(list.files(cache, recursive = TRUE), 0L)
})

test_that("Hub errors remain informative with or without the URL fallback", {
    path <- tempfile("spamtpdb-hub-")
    dir.create(path)
    on.exit(unlink(path, recursive = TRUE), add = TRUE)
    fixture <- data.frame(value = 1)
    filename <- file.path(path, "fixture.rds")
    saveRDS(fixture, filename)
    state <- new.env(parent = emptyenv())
    state$calls <- 0L
    local_mocked_bindings(
        AnnotationHub = function(...) stop("Hub unavailable"),
        .spamtpdb_download = function(...) {
            state$calls <- state$calls + 1L
            filename
        }
    )
    args <- list(resource = "chem_props", local_dir = file.path(path, "empty"),
                 cache_dir = file.path(path, "cache"))
    expect_error(do.call(spaMTPdbResource, c(args, list(fallback_url = FALSE))),
                 "AnnotationHub could not provide.*Hub unavailable")
    expect_identical(state$calls, 0L)
    expect_identical(do.call(spaMTPdbResource, args), fixture)
    expect_identical(state$calls, 1L)
})

test_that("a successful Hub lookup returns the resource without a fallback", {
    path <- tempfile("spamtpdb-hub-success-")
    row <- spaMTPdbResource("chem_props", metadata = TRUE)
    fixture <- data.frame(value = 1)
    local_mocked_bindings(
        AnnotationHub = function(...) list(),
        query = function(...) list(fixture),
        mcols = function(...) data.frame(title = row$title),
        .spamtpdb_download = function(...) stop("unexpected URL fallback")
    )
    expect_identical(spaMTPdbResource("chem_props", local_dir = path,
                                     cache_dir = path), fixture)
})
