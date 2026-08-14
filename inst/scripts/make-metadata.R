#!/usr/bin/env Rscript

if (!requireNamespace("AnnotationHubData", quietly = TRUE)) {
    stop("Install AnnotationHubData before validating Hub metadata.")
}
script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_path <- sub("^--file=", "", script_arg)
package_root <- normalizePath(
    file.path(dirname(script_path), "..", ".."), mustWork = TRUE
)
AnnotationHubData::makeAnnotationHubMetadata(package_root)
