.spamtpdb_manifest <- function() {
    ## The manifest lives outside inst/extdata because AnnotationHubData reads
    ## every CSV in that directory as Hub metadata.
    path <- system.file(
        "manifest", "resource_manifest.csv", package = "SpaMTPdb"
    )
    if (!nzchar(path)) {
        stop("SpaMTPdb resource manifest is unavailable.", call. = FALSE)
    }
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

.spamtpdb_resolve_version <- function(manifest, version) {
    versions <- unique(as.character(manifest$version))
    if (is.null(version) || identical(version, "latest")) {
        latest <- tail(sort(package_version(versions)), 1L)
        return(as.character(latest))
    }
    version <- as.character(version)[1L]
    if (!version %in% versions) {
        stop(
            "SpaMTPdb version '", version, "' is unavailable. Available: ",
            paste(versions, collapse = ", "),
            call. = FALSE
        )
    }
    version
}

.spamtpdb_local_dir <- function(local_dir = NULL) {
    if (!is.null(local_dir)) {
        return(normalizePath(local_dir, mustWork = FALSE))
    }
    configured <- getOption("SpaMTPdb.resource_dir", "")
    if (!nzchar(configured)) {
        configured <- Sys.getenv("SPAMTPDB_RESOURCE_DIR", "")
    }
    if (!nzchar(configured)) {
        NULL
    } else {
        normalizePath(configured, mustWork = FALSE)
    }
}

.spamtpdb_local_file <- function(row, local_dir) {
    if (is.null(local_dir)) return(NULL)
    candidates <- unique(c(
        file.path(local_dir, row$version, row$file_name),
        file.path(local_dir, row$file_name),
        file.path(local_dir, paste0(row$resource, "_", row$version, ".rds")),
        file.path(local_dir, paste0(row$resource, ".rds"))
    ))
    found <- candidates[file.exists(candidates)]
    if (length(found)) found[[1L]] else NULL
}

.spamtpdb_read_local <- function(path, dispatch_class) {
    if (tolower(dispatch_class) %in% c("rds", "rda")) {
        if (tolower(dispatch_class) == "rds") return(readRDS(path))
        environment <- new.env(parent = emptyenv())
        loaded <- load(path, envir = environment)
        if (length(loaded) != 1L) {
            stop(
                "Local Rda resource must contain exactly one object.",
                call. = FALSE
            )
        }
        return(environment[[loaded]])
    }
    normalizePath(path, mustWork = TRUE)
}

.spamtpdb_cache_dir <- function(cache_dir = NULL, create = TRUE) {
    if (is.null(cache_dir)) {
        cache_dir <- getOption("SpaMTPdb.cache_dir", "")
    }
    if (!nzchar(cache_dir)) {
        cache_dir <- Sys.getenv("SPAMTPDB_CACHE_DIR", "")
    }
    if (!nzchar(cache_dir)) {
        cache_dir <- tools::R_user_dir("SpaMTPdb", which = "cache")
    }
    if (create) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    normalizePath(cache_dir, mustWork = create)
}

.spamtpdb_file_valid <- function(path, row) {
    if (!file.exists(path) || isTRUE(file.info(path)$isdir)) return(FALSE)
    expected_bytes <- suppressWarnings(as.numeric(row$bytes[[1L]]))
    if (length(expected_bytes) != 1L || !is.finite(expected_bytes) ||
        expected_bytes <= 0 || file.info(path)$size != expected_bytes) {
        return(FALSE)
    }
    expected_md5 <- tolower(as.character(row$md5[[1L]]))
    if (length(expected_md5) != 1L || is.na(expected_md5) ||
        !grepl("^[0-9a-f]{32}$", expected_md5)) return(FALSE)
    identical(tolower(unname(tools::md5sum(path))), expected_md5)
}

.spamtpdb_cached_file <- function(row, cache_dir = NULL) {
    root <- .spamtpdb_cache_dir(cache_dir, create = FALSE)
    paths <- c(file.path(root, row$version, row$file_name),
               file.path(root, row$file_name))
    valid <- vapply(paths, .spamtpdb_file_valid, logical(1), row = row)
    if (any(valid)) paths[which(valid)[1L]] else NULL
}

.spamtpdb_verify_local <- function(path, row, verify) {
    if (verify && !.spamtpdb_file_valid(path, row)) {
        stop("Local resource '", row$resource, "' failed its size or MD5 check. ",
             "Use verify = FALSE only for intentional development fixtures, ",
             "not to label modified data as an official release.", call. = FALSE)
    }
    path
}

.spamtpdb_download <- function(row, cache_dir = NULL, timeout = 1800,
                               retries = 3L) {
    cache_dir <- .spamtpdb_cache_dir(cache_dir)
    version_dir <- file.path(cache_dir, as.character(row$version[[1L]]))
    dir.create(version_dir, recursive = TRUE, showWarnings = FALSE)
    destination <- file.path(version_dir, as.character(row$file_name[[1L]]))
    if (.spamtpdb_file_valid(destination, row)) return(destination)

    url <- paste0(
        as.character(row$location_prefix[[1L]]),
        as.character(row$rdata_path[[1L]])
    )
    retries <- suppressWarnings(as.integer(retries)[1L])
    if (is.na(retries) || retries < 1L) retries <- 1L
    timeout <- suppressWarnings(as.numeric(timeout)[1L])
    if (!is.finite(timeout) || timeout < 1) timeout <- 1800
    old_timeout <- getOption("timeout")
    old_timeout_numeric <- suppressWarnings(as.numeric(old_timeout)[1L])
    if (!is.finite(old_timeout_numeric)) old_timeout_numeric <- 60
    options(timeout = max(old_timeout_numeric, timeout))
    on.exit(options(timeout = old_timeout), add = TRUE)

    last_error <- NULL
    for (attempt in seq_len(retries)) {
        partial <- paste0(destination, ".part-", Sys.getpid())
        on.exit(unlink(partial), add = TRUE)
        result <- tryCatch(
            {
                download.file(
                    url,
                    destfile = partial,
                    method = "libcurl",
                    mode = "wb",
                    quiet = TRUE
                )
                if (!.spamtpdb_file_valid(partial, row)) {
                    stop("downloaded file failed its size or MD5 check")
                }
                if (file.exists(destination)) unlink(destination)
                if (!file.rename(partial, destination)) {
                    stop("could not move the verified file into the cache")
                }
                destination
            },
            error = function(error) {
                last_error <<- conditionMessage(error)
                unlink(partial)
                NULL
            }
        )
        if (!is.null(result)) return(result)
    }
    stop(
        "Failed to download verified SpaMTPdb resource '", row$resource,
        "' after ", retries, " attempt(s): ", last_error,
        call. = FALSE
    )
}

.spamtpdb_check_class <- function(value, row) {
    expected <- strsplit(row$r_data_class, "/", fixed = TRUE)[[1L]]
    valid <- vapply(
        expected,
        function(expected_class) inherits(value, expected_class),
        logical(1)
    )
    if (!any(valid)) {
        stop(
            "Resource '", row$resource, "' has class ",
            paste(class(value), collapse = "/"), "; expected ",
            paste(expected, collapse = "/"), ".",
            call. = FALSE
        )
    }
    value
}

#' List SpaMTPdb resources
#'
#' @param version RaMP/SpaMTPdb resource version. `NULL` selects all versions.
#' @param category Optional resource category.
#' @param default_only Return only resources used by the default SpaMTP
#'   annotation and pathway pipelines.
#'
#' @return A data frame describing available resources.
#' @export
#'
#' @examples
#' spaMTPdbResources(default_only = TRUE)
spaMTPdbResources <- function(version = NULL, category = NULL,
                              default_only = FALSE) {
    manifest <- .spamtpdb_manifest()
    if (!is.null(version)) {
        version <- .spamtpdb_resolve_version(manifest, version)
        manifest <- manifest[manifest$version == version, , drop = FALSE]
    }
    if (!is.null(category)) {
        manifest <- manifest[manifest$category %in% category, , drop = FALSE]
    }
    if (isTRUE(default_only)) {
        manifest <- manifest[manifest$default, , drop = FALSE]
    }
    rownames(manifest) <- NULL
    manifest
}

#' Retrieve one SpaMTP annotation resource
#'
#' Resources are resolved in order: a staged local directory (`local_dir`, the
#' `SpaMTPdb.resource_dir` option, or the `SPAMTPDB_RESOURCE_DIR` environment
#' variable), a verified download cache, then the matching AnnotationHub record,
#' and finally the immutable
#' Zenodo source URL recorded in the resource manifest. Files retrieved from
#' Zenodo and local files are verified against the recorded size and MD5
#' checksum. The verified download cache is usable with `offline = TRUE`.
#'
#' @param resource Resource name; see [spaMTPdbResources()].
#' @param version Resource version or `"latest"`.
#' @param local_dir Optional directory containing staged `.rds` resources.
#' @param hub Optional pre-created `AnnotationHub` object.
#' @param metadata Return the registry row without loading the resource.
#' @param offline If `TRUE`, use local files or a verified cache only; never
#'   query AnnotationHub or Zenodo.
#' @param fallback_url If `TRUE`, use the immutable Zenodo source URL when the
#'   resource has not yet been ingested into AnnotationHub.
#' @param cache_dir Cache directory for source-URL downloads. Defaults to the
#'   platform-specific user cache returned by [tools::R_user_dir()].
#' @param timeout Download timeout in seconds for the source-URL fallback.
#' @param retries Number of verified download attempts.
#' @param verify Verify local files against the published size and checksum.
#'   Set to `FALSE` only for intentional development fixtures. Downloaded and
#'   cached files are always verified; loaded object classes are always checked.
#'
#' @return The requested R object, or its registry row when `metadata = TRUE`.
#' @export
#'
#' @examples
#' spaMTPdbResource("chem_props", metadata = TRUE)
spaMTPdbResource <- function(resource, version = "latest", local_dir = NULL,
                             hub = NULL, metadata = FALSE, offline = FALSE,
                             fallback_url = TRUE, cache_dir = NULL,
                             timeout = 1800, retries = 3L, verify = TRUE) {
    if (length(resource) != 1L || is.na(resource) || !nzchar(trimws(resource))) {
        stop("resource must be one non-empty name.", call. = FALSE)
    }
    if (!is.logical(verify) || length(verify) != 1L || is.na(verify)) {
        stop("verify must be TRUE or FALSE.", call. = FALSE)
    }
    manifest <- .spamtpdb_manifest()
    version <- .spamtpdb_resolve_version(manifest, version)
    key <- tolower(as.character(resource)[1L])
    rows <- manifest[
        tolower(manifest$resource) == key & manifest$version == version,
        , drop = FALSE
    ]
    if (nrow(rows) != 1L) {
        stop(
            "Unknown SpaMTPdb resource '", resource, "' for version ",
            version, ". Use spaMTPdbResources() to list valid names.",
            call. = FALSE
        )
    }
    if (isTRUE(metadata)) return(rows)

    local_file <- .spamtpdb_local_file(rows, .spamtpdb_local_dir(local_dir))
    if (!is.null(local_file)) {
        .spamtpdb_verify_local(local_file, rows, verify)
        return(.spamtpdb_check_class(
            .spamtpdb_read_local(local_file, rows$dispatch_class), rows
        ))
    }
    cached <- .spamtpdb_cached_file(rows, cache_dir)
    if (!is.null(cached)) {
        return(.spamtpdb_check_class(
            .spamtpdb_read_local(cached, rows$dispatch_class), rows))
    }
    if (isTRUE(offline)) {
        stop(
            "Resource '", resource, "' is not present in the configured local ",
            "directory or verified cache and offline = TRUE.",
            call. = FALSE
        )
    }

    hub_error <- NULL
    value <- tryCatch(
        {
            if (is.null(hub)) hub <- AnnotationHub()
            hits <- query(hub, c("SpaMTPdb", rows$title))
            hit_metadata <- as.data.frame(mcols(hits))
            exact <- which(as.character(hit_metadata$title) == rows$title)
            if (!length(exact)) {
                stop("resource has not yet been ingested into AnnotationHub")
            }
            hits[[exact[[1L]]]]
        },
        error = function(error) {
            hub_error <<- conditionMessage(error)
            NULL
        }
    )
    if (!is.null(value)) return(.spamtpdb_check_class(value, rows))
    if (isTRUE(fallback_url)) {
        path <- .spamtpdb_download(
            rows,
            cache_dir = cache_dir,
            timeout = timeout,
            retries = retries
        )
        return(.spamtpdb_check_class(
            .spamtpdb_read_local(path, rows$dispatch_class), rows
        ))
    }
    stop(
        "AnnotationHub could not provide '", rows$title, "': ", hub_error,
        ". Configure a local resource directory or set fallback_url = TRUE.",
        call. = FALSE
    )
}

#' Retrieve a coherent set of SpaMTP annotation resources
#'
#' @param resources Character vector of resource names. By default, all core
#'   resources used by SpaMTP are returned.
#' @param version Resource version or `"latest"`.
#' @param ... Passed to [spaMTPdbResource()].
#'
#' @return A named list of resources from one database version.
#' @export
#'
#' @examples
#' spaMTPdbBundle(resources = "chem_props", metadata = TRUE)
spaMTPdbBundle <- function(
    resources = NULL,
    version = "latest", ...
) {
    version <- .spamtpdb_resolve_version(.spamtpdb_manifest(), version)
    if (is.null(resources)) {
        resources <- spaMTPdbResources(version = version, default_only = TRUE)$resource
    }
    result <- lapply(
        resources,
        spaMTPdbResource,
        version = version,
        ...
    )
    stats::setNames(result, resources)
}

#' Report the available SpaMTPdb versions
#'
#' @return A character vector of resource versions, newest first.
#' @export
#'
#' @examples
#' spaMTPdbVersion()
spaMTPdbVersion <- function() {
    versions <- unique(as.character(.spamtpdb_manifest()$version))
    rev(as.character(sort(package_version(versions))))
}
