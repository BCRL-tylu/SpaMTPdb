.spamtpdb_manifest <- function() {
    path <- system.file("extdata", "resource_manifest.csv", package = "SpaMTPdb")
    if (!nzchar(path)) {
        stop("SpaMTPdb resource manifest is unavailable.", call. = FALSE)
    }
    utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

.spamtpdb_resolve_version <- function(manifest, version) {
    versions <- unique(as.character(manifest$version))
    if (is.null(version) || identical(version, "latest")) {
        return(utils::tail(sort(package_version(versions)), 1L) |> as.character())
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
    if (!nzchar(configured)) NULL else normalizePath(configured, mustWork = FALSE)
}

.spamtpdb_local_file <- function(row, local_dir) {
    if (is.null(local_dir)) return(NULL)
    candidates <- unique(c(
        file.path(local_dir, basename(row$rdata_path)),
        file.path(local_dir, row$rdata_path),
        file.path(local_dir, paste0(row$resource, "_", row$version, ".rds")),
        file.path(local_dir, paste0(row$resource, ".rds"))
    ))
    found <- candidates[file.exists(candidates)]
    if (length(found)) found[[1L]] else NULL
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
#' SpaMTPdbResources(default_only = TRUE)
SpaMTPdbResources <- function(version = NULL, category = NULL,
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
#' Resources are first resolved from `local_dir`, the
#' `SpaMTPdb.resource_dir` option, or the `SPAMTPDB_RESOURCE_DIR` environment
#' variable. If no local file exists, the matching AnnotationHub record is
#' retrieved and cached by AnnotationHub.
#'
#' @param resource Resource name; see [SpaMTPdbResources()].
#' @param version Resource version or `"latest"`.
#' @param local_dir Optional directory containing staged `.rds` resources.
#' @param hub Optional pre-created `AnnotationHub` object.
#' @param metadata Return the registry row without loading the resource.
#' @param offline If `TRUE`, never query AnnotationHub.
#'
#' @return The requested R object, or its registry row when `metadata = TRUE`.
#' @export
#'
#' @examples
#' SpaMTPdbResource("chem_props", metadata = TRUE)
SpaMTPdbResource <- function(resource, version = "latest", local_dir = NULL,
                             hub = NULL, metadata = FALSE, offline = FALSE) {
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
            version, ". Use SpaMTPdbResources() to list valid names.",
            call. = FALSE
        )
    }
    if (isTRUE(metadata)) return(rows)

    local_file <- .spamtpdb_local_file(rows, .spamtpdb_local_dir(local_dir))
    if (!is.null(local_file)) {
        return(.spamtpdb_check_class(readRDS(local_file), rows))
    }
    if (isTRUE(offline)) {
        stop(
            "Resource '", resource, "' is not present in the configured local ",
            "directory and offline = TRUE.",
            call. = FALSE
        )
    }

    if (is.null(hub)) hub <- AnnotationHub::AnnotationHub()
    hits <- AnnotationHub::query(hub, c("SpaMTPdb", rows$title))
    hit_metadata <- as.data.frame(S4Vectors::mcols(hits))
    exact <- which(as.character(hit_metadata$title) == rows$title)
    if (!length(exact)) {
        stop(
            "AnnotationHub does not yet contain '", rows$title, "'. Configure ",
            "options(SpaMTPdb.resource_dir = ...) for a staged development ",
            "resource.",
            call. = FALSE
        )
    }
    .spamtpdb_check_class(hits[[exact[[1L]]]], rows)
}

#' Retrieve a coherent set of SpaMTP annotation resources
#'
#' @param resources Character vector of resource names. By default, all core
#'   resources used by SpaMTP are returned.
#' @param version Resource version or `"latest"`.
#' @param ... Passed to [SpaMTPdbResource()].
#'
#' @return A named list of resources from one database version.
#' @export
#'
#' @examples
#' SpaMTPdbBundle(resources = "chem_props", metadata = TRUE)
SpaMTPdbBundle <- function(
    resources = SpaMTPdbResources(version = "latest", default_only = TRUE)$resource,
    version = "latest", ...
) {
    result <- lapply(
        resources,
        SpaMTPdbResource,
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
#' SpaMTPdbVersion()
SpaMTPdbVersion <- function() {
    versions <- unique(as.character(.spamtpdb_manifest()$version))
    rev(as.character(sort(package_version(versions))))
}
