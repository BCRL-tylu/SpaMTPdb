#!/usr/bin/env Rscript

# Default: local validation only. Never publishes, edits published files or deletes files.
# Usage: upload-shared-release.R STAGING [--create-version | --draft-id ID] [--upload]
args <- commandArgs(trailingOnly = TRUE)
usage <- paste("Usage: upload-shared-release.R STAGING",
    "[--create-version | --draft-id ID] [--upload]; default is an offline dry run.")
if (!length(args)) stop(usage, call. = FALSE)
staging <- normalizePath(args[[1L]], mustWork = TRUE)
create <- FALSE
transfer <- FALSE
draftId <- NULL
i <- 2L
while (i <= length(args)) {
    flag <- args[[i]]
    if (flag == "--create-version") create <- TRUE else if (flag == "--upload") {
        transfer <- TRUE
    } else if (flag == "--draft-id" && i < length(args)) {
        i <- i + 1L
        draftId <- args[[i]]
    } else stop("Unsupported option: ", flag, ". ", usage, call. = FALSE)
    i <- i + 1L
}
if (create && !is.null(draftId)) stop("Choose create-version or draft-id, not both.")
for (package in c("jsonlite", "httr2")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("Install ", package, ".")
}
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(),
    value = TRUE)[1L]), mustWork = TRUE)
source(file.path(dirname(script), "shared-release-utils.R"))
planFile <- file.path(staging, "upload-plan.csv")
plan <- releaseReadCsv(planFile)
releaseCheckFiles(plan)
config <- jsonlite::read_json(file.path(staging, "release-config.json"))
metadata <- jsonlite::read_json(file.path(staging, "zenodo-metadata.draft.json"))
releaseRequire(identical(metadata$metadata$version, config$collection_version) &&
    identical(metadata$metadata$title, config$title), "Metadata/config version or title differs.")
message("Validated ", nrow(plan), " whitelisted files (",
    format(sum(plan$bytes) / 1e6, digits = 5), " MB).")
if (!create && is.null(draftId) && !transfer) {
    message("Offline dry run: no network, draft creation, upload or publication.")
    quit(save = "no", status = 0L)
}
stateFile <- file.path(staging, "upload-state.json")
state <- if (file.exists(stateFile)) jsonlite::read_json(stateFile) else NULL
planMd5 <- unname(tools::md5sum(planFile))
if (!is.null(state)) {
    releaseRequire(identical(state$plan_md5, planMd5) &&
        identical(state$base_record_id, config$base_record_id),
        "Saved upload state belongs to another plan; review it before proceeding.")
    if (!is.null(draftId)) releaseRequire(identical(draftId, state$draft_id),
        "Explicit draft ID differs from saved upload state.")
    draftId <- state$draft_id
    create <- FALSE
}
releaseRequire(create || !is.null(draftId),
    "Use --create-version, --draft-id ID, or resume a saved upload with --upload.")
releaseRequire(is.null(draftId) || grepl("^[0-9]+$", draftId), "Draft ID must be numeric.")
token <- Sys.getenv("ZENODO_TOKEN", "")
releaseRequire(nzchar(token), paste("Set ZENODO_TOKEN locally; never paste it into logs/chat.",
    "Existing drafts need deposit:write. Creating a new version also needs deposit:actions."))
host <- "https://zenodo.org"
api <- function(path, method = "GET", body = NULL) {
    releaseRequire(grepl("^/api/(records/[0-9]+|deposit/depositions/[0-9]+(/actions/newversion)?)$",
        path), "Unexpected API operation.")
    request <- httr2::request(paste0(host, path))
    request <- httr2::req_headers(request, Authorization = paste("Bearer", token))
    request <- httr2::req_method(request, method)
    request <- httr2::req_timeout(request, 120)
    if (!is.null(body)) request <- httr2::req_body_json(request, body, auto_unbox = TRUE)
    httr2::resp_body_json(httr2::req_perform(request), simplifyVector = FALSE)
}
base <- api(paste0("/api/records/", config$base_record_id))
releaseRequire(isTRUE(base$submitted) && identical(base$status, "published") &&
    identical(as.character(base$conceptrecid), config$concept_record_id),
    "Configured base record is not a published member of the expected version family.")
resources <- releaseReadCsv(file.path(staging, "resource_manifest.csv"))
database <- resources[resources$owner_package == "SpaMTPdb", , drop = FALSE]
releaseCheckRemote(database, base, complete = TRUE)
if (create) {
    # API response is the OLD record. Follow latest_draft, never use its id as the new id.
    response <- api(paste0("/api/deposit/depositions/", config$base_record_id,
        "/actions/newversion"), "POST")
    link <- releaseSafeUrl(response$links$latest_draft, host, "/api/deposit/depositions/")
    draftId <- sub("^.*/", "", link)
    releaseRequire(grepl("^[0-9]+$", draftId), "Invalid latest_draft identifier.")
}
draft <- api(paste0("/api/deposit/depositions/", draftId))
releaseCheckDraft(draft, config)
releaseSafeUrl(draft$links$bucket, host, "/api/files/")
releaseCheckRemote(plan, draft)
jsonlite::write_json(list(base_record_id = config$base_record_id,
    draft_id = draftId, plan_md5 = planMd5), stateFile, pretty = TRUE, auto_unbox = TRUE)
message("Verified version-family draft ", draftId, ": https://zenodo.org/deposit/", draftId)
if (!transfer) {
    message("No files uploaded. Use --upload to resume this staged plan. Nothing published.")
    quit(save = "no", status = 0L)
}
upload <- function(bucket, row) {
    bucket <- releaseSafeUrl(bucket, host, "/api/files/")
    request <- httr2::request(paste0(bucket, "/", row$file_name))
    request <- httr2::req_headers(request, Authorization = paste("Bearer", token))
    request <- httr2::req_method(request, "PUT")
    request <- httr2::req_body_file(request, row$local_path)
    request <- httr2::req_timeout(request, 3600)
    response <- httr2::resp_body_json(httr2::req_perform(request), simplifyVector = FALSE)
    releaseCheckRemote(row, list(files = list(response)), complete = TRUE)
    message("Verified upload: ", row$file_name)
}
releaseUpload(plan, config, metadata, draft, api, upload)
message("All files verified. Draft remains UNPUBLISHED; review metadata and publish manually.")
