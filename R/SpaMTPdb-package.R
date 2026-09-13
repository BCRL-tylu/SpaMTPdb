#' SpaMTPdb: annotation resources for SpaMTP
#'
#' `SpaMTPdb` provides version-aware access to RaMP-derived chemical,
#' identifier, pathway, pathway-network, and precomputed SMILES ionisation
#' resources. Large resources are retrieved through AnnotationHub; package
#' developers may instead configure a directory containing staged `.rds`
#' files.
#'
#' @importFrom AnnotationHub AnnotationHub query
#' @importFrom S4Vectors mcols
#' @importFrom utils download.file read.csv tail
#' @keywords internal
"_PACKAGE"
