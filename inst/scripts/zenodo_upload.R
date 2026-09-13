#!/usr/bin/env Rscript

# Compatibility entry point for the shared, draft-only publication workflow.
# Usage: zenodo_upload.R STAGING [--create-version | --draft-id ID] [--upload]
# Previous positional arguments and --publish are intentionally not supported.
argument <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script <- normalizePath(sub("^--file=", "", argument), mustWork = TRUE)
recipe <- file.path(dirname(script), "upload-shared-release.R")
status <- system2(file.path(R.home("bin"), "Rscript"),
    c(shQuote(recipe), shQuote(commandArgs(trailingOnly = TRUE))))
quit(save = "no", status = status)
