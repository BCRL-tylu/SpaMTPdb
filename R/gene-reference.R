.spamtpdb_gene_manifest <- function() {
    path <- system.file("manifest", "gene_reference_manifest.csv", package = "SpaMTPdb")
    if (!nzchar(path)) stop("SpaMTPdb gene reference manifest is unavailable.", call. = FALSE)
    utils::read.csv(path, stringsAsFactors = FALSE)
}

#' Retrieve a versioned human gene identifier reference
#'
#' Retrieves a fixed HGNC quarterly archive, independently of the RaMP resource
#' version. The archive contains approved symbols, previous and alias symbols,
#' HGNC, Entrez, Ensembl and UniProt identifiers. It is an annotation resource;
#' experiment data continue to be supplied by SpaMTPData.
#'
#' Files are resolved from a local directory, verified cache, then the official
#' HGNC archive URL. Size and MD5 are checked before parsing. No live symbol
#' queries or changing HGNC "current" downloads are used. The large reference
#' file is not included in the installed package. This reference covers human
#' genes and does not implement orthology mapping.
#'
#' @param version HGNC archive version or `"latest"`, resolved only against the
#'   gene reference registry, independently of [spaMTPdbVersion()].
#' @param local_dir Directory containing the archived TSV, optionally under a
#'   version subdirectory. Defaults to `SpaMTPdb.gene_reference_dir` or the
#'   `SPAMTPDB_GENE_REFERENCE_DIR` environment variable.
#' @param metadata Return the version registry row without reading/downloading.
#' @param offline Use local files or a verified cache only.
#' @param cache_dir Download cache root; see [spaMTPdbResource()].
#' @param timeout Download timeout in seconds.
#' @param retries Number of verified download attempts.
#'
#' @return A data frame with an attribute `spamtp_gene_reference` recording the
#'   HGNC version, organism, source URL and checksum; or a metadata row.
#' @export
#' @examples
#' spaMTPdbGeneReference(metadata = TRUE)
spaMTPdbGeneReference <- function(version = "latest", local_dir = NULL,
                                  metadata = FALSE, offline = FALSE,
                                  cache_dir = NULL, timeout = 1800, retries = 3L) {
    manifest <- .spamtpdb_gene_manifest()
    version <- .spamtpdb_resolve_version(manifest, version)
    row <- manifest[manifest$version == version, , drop = FALSE]
    if (nrow(row) != 1L) stop("Gene reference version is not unique.", call. = FALSE)
    if (isTRUE(metadata)) return(row)
    if (is.null(local_dir)) {
        local_dir <- getOption("SpaMTPdb.gene_reference_dir", "")
        if (!nzchar(local_dir)) local_dir <- Sys.getenv("SPAMTPDB_GENE_REFERENCE_DIR", "")
        if (!nzchar(local_dir)) local_dir <- NULL
    }
    path <- .spamtpdb_local_file(row, local_dir)
    if (!is.null(path)) {
        .spamtpdb_verify_local(path, row, TRUE)
    } else {
        path <- .spamtpdb_cached_file(row, cache_dir)
    }
    if (is.null(path)) {
        if (isTRUE(offline)) {
            stop("HGNC gene reference is absent from local files and verified cache; offline = TRUE.",
                 call. = FALSE)
        }
        path <- .spamtpdb_download(row, cache_dir, timeout, retries)
    }
    value <- utils::read.delim(path, quote = "\"", comment.char = "",
                              colClasses = "character", check.names = FALSE)
    required <- c("hgnc_id", "symbol", "status", "prev_symbol", "alias_symbol",
                  "entrez_id", "ensembl_gene_id", "uniprot_ids")
    if (!all(required %in% names(value))) {
        stop("HGNC reference is missing required identifier columns.", call. = FALSE)
    }
    attr(value, "spamtp_gene_reference") <- list(
        provider = "SpaMTPdb", resource = "hgnc_gene_reference", version = version,
        organism = "Homo sapiens", taxonomy_id = 9606L,
        source_url = paste0(row$location_prefix, row$rdata_path), md5 = row$md5
    )
    value
}
