#!/usr/bin/env Rscript

## Deposit the staged SpaMTPdb resource files on Zenodo.
##
## Bioconductor no longer hosts Hub resources for external contributors, so the
## processed files are published on Zenodo and the AnnotationHub records point
## at that copy. This script creates the deposition and uploads the staged
## files; it deliberately stops short of publishing, because publishing mints a
## permanent DOI and cannot be undone.
##
## Usage:
##   export ZENODO_TOKEN=...      # scopes: deposit:write, deposit:actions
##   Rscript inst/scripts/zenodo_upload.R [resource_dir] [version] [--sandbox] [--publish]
##
## resource_dir  Directory holding <version>/<resource>.rds. Default ../SpaMTPdb-resources.
## version       Resource version to deposit. Default 3.0.7.
## --sandbox     Use sandbox.zenodo.org for a rehearsal run.
## --publish     Publish the deposition after uploading. Omit to leave a draft
##               for review in the Zenodo web interface.
##
## After the deposition exists, record its ID and regenerate the Hub metadata:
##   Rscript inst/scripts/stage_resources.R ../SpaMTP ../SpaMTPdb-resources 3.0.7 <record_id>
##   Rscript inst/scripts/make-metadata.R

for (package in c("httr2", "jsonlite")) {
    if (!requireNamespace(package, quietly = TRUE)) {
        stop("Install ", package, " before depositing resources.", call. = FALSE)
    }
}

args <- commandArgs(trailingOnly = TRUE)
flags <- grepl("^--", args)
positional <- args[!flags]
flags <- args[flags]

resource_dir <- if (length(positional) >= 1L) positional[[1L]] else "../SpaMTPdb-resources"
version <- if (length(positional) >= 2L) positional[[2L]] else "3.0.7"
sandbox <- "--sandbox" %in% flags
publish <- "--publish" %in% flags

token <- Sys.getenv(if (sandbox) "ZENODO_SANDBOX_TOKEN" else "ZENODO_TOKEN", "")
if (!nzchar(token)) {
    stop(
        "Set ", if (sandbox) "ZENODO_SANDBOX_TOKEN" else "ZENODO_TOKEN",
        " to a Zenodo personal access token with the deposit:write and ",
        "deposit:actions scopes.",
        call. = FALSE
    )
}

host <- if (sandbox) "https://sandbox.zenodo.org" else "https://zenodo.org"
version_dir <- normalizePath(file.path(resource_dir, version), mustWork = TRUE)
files <- sort(list.files(version_dir, pattern = "\\.rds$", full.names = TRUE))
if (!length(files)) {
    stop("No .rds resources found in ", version_dir, call. = FALSE)
}

message(
    "Depositing ", length(files), " files (",
    format(sum(file.info(files)$size) / 1e6, digits = 4), " MB) to ", host
)

description <- paste0(
    "<p>Processed annotation resources for the <a href=\"",
    "https://bioconductor.org/packages/SpaMTPdb\">SpaMTPdb</a> Bioconductor ",
    "annotation package, the data companion to SpaMTP.</p>",
    "<p>This deposition is an immutable, pruned snapshot derived from NCATS ",
    "RaMP-DB ", version, ", together with harmonised pathway topology for HMDB, ",
    "KEGG, Reactome and WikiPathways, legacy metabolite reference tables, and a ",
    "SMILES-derived functional-group and adduct-prior feature table. Resources ",
    "are stored as independent RDS files so that an analysis downloads only the ",
    "components it needs.</p>",
    "<p>Resource versions are immutable. Future RaMP releases are deposited as ",
    "new versions of this record rather than replacing this snapshot, so an ",
    "analysis can record and reproduce the exact database version it used.</p>",
    "<p>These files are registered in the Bioconductor AnnotationHub; see the ",
    "SpaMTPdb package for versioned access functions.</p>"
)

metadata <- list(
    metadata = list(
        title = paste0(
            "SpaMTPdb: versioned annotation resources for SpaMTP (RaMP-DB ",
            version, " snapshot)"
        ),
        upload_type = "dataset",
        description = description,
        version = version,
        creators = list(
            list(name = "Lu, Tianyao", affiliation = "WEHI"),
            list(name = "Causer, Andrew"),
            list(name = "Nguyen, Quan")
        ),
        license = "cc-by-4.0",
        communities = list(list(identifier = "spamtp")),
        keywords = list(
            "spatial metabolomics", "mass spectrometry imaging",
            "metabolite annotation", "pathway analysis", "RaMP-DB",
            "Bioconductor", "AnnotationHub"
        ),
        related_identifiers = list(
            list(
                relation = "isSupplementTo",
                identifier = "10.1038/s41592-026-03140-8",
                scheme = "doi"
            ),
            list(
                relation = "isDerivedFrom",
                identifier = "https://github.com/ncats/RaMP-DB",
                scheme = "url"
            )
        )
    )
)

api <- function(path, method = "GET", body = NULL) {
    request <- httr2::request(paste0(host, path))
    request <- httr2::req_headers(request, Authorization = paste("Bearer", token))
    request <- httr2::req_method(request, method)
    if (!is.null(body)) request <- httr2::req_body_json(request, body)
    httr2::resp_body_json(httr2::req_perform(request))
}

deposition <- api("/api/deposit/depositions", "POST", metadata)
record_id <- deposition$id
bucket <- deposition$links$bucket
message("Created draft deposition ", record_id, " (", deposition$links$html, ")")

for (file in files) {
    name <- basename(file)
    size <- file.info(file)$size
    message("  uploading ", name, " (", format(size / 1e6, digits = 4), " MB)")
    request <- httr2::request(paste0(bucket, "/", name))
    request <- httr2::req_headers(request, Authorization = paste("Bearer", token))
    request <- httr2::req_method(request, "PUT")
    request <- httr2::req_body_file(request, file)
    request <- httr2::req_timeout(request, 3600)
    httr2::req_perform(request)
}

if (publish) {
    published <- api(
        paste0("/api/deposit/depositions/", record_id, "/actions/publish"), "POST"
    )
    message(
        "Published record ", published$id, " with DOI ", published$doi, "\n",
        "  ", published$links$record_html
    )
    record_id <- published$id
} else {
    message(
        "\nDraft left unpublished. Review it at:\n  ", deposition$links$html,
        "\nPublishing mints a permanent DOI; re-run with --publish, or publish ",
        "from the web interface."
    )
}

message(
    "\nNext, regenerate the Hub metadata against this record:\n",
    "  Rscript inst/scripts/stage_resources.R ../SpaMTP ", resource_dir, " ",
    version, " ", record_id, "\n",
    "  Rscript inst/scripts/make-metadata.R"
)
