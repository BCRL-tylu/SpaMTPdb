#' SpaMTPdb: annotation resources for SpaMTP
#'
#' `SpaMTPdb` provides version-aware access to RaMP-derived chemical,
#' identifier, pathway, pathway-network, and precomputed SMILES ionisation
#' resources, plus a separately versioned human HGNC gene reference. RaMP
#' resources are retrieved through AnnotationHub with a verified Zenodo
#' fallback; the gene reference uses a fixed HGNC archive. Local files and
#' verified cached downloads support offline use.
#'
#' @importFrom AnnotationHub AnnotationHub query
#' @importFrom S4Vectors mcols
#' @importFrom utils download.file read.csv tail
#' @keywords internal
"_PACKAGE"
