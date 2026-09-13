#!/usr/bin/env Rscript

## Generate and validate inst/extdata/metadata.csv for the AnnotationHub.
##
## Usage:
##   Rscript inst/scripts/make-metadata.R [--validate-only]
##
## The Hub record for each resource is derived from inst/manifest/resource_manifest.csv,
## which stage_resources.R writes after staging the files and recording the
## Zenodo record that hosts them. The resource files are hosted on Zenodo rather
## than in the Bioconductor Hub bucket, so Location_Prefix points at the Zenodo
## REST API and RDataPath carries the per-file content path.

args <- commandArgs(trailingOnly = TRUE)
validate_only <- "--validate-only" %in% args

script_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
script_path <- sub("^--file=", "", script_arg)
package_root <- normalizePath(
    file.path(dirname(script_path), "..", ".."), mustWork = TRUE
)

bioc_version <- "3.24"

## Provenance is per resource and independent of where the processed files are
## hosted: SourceUrl records the upstream database the resource is derived from,
## while Location_Prefix/RDataPath record the download location.
##
## SourceType must come from the controlled vocabulary that AnnotationHubData
## enforces, which has no SQLite term. RaMP-DB is released as a MySQL dump
## alongside its SQLite build, so RaMP-derived resources are recorded as MySQL.
annotations <- list(
    chem_props = list(
        description = "Pruned RaMP chemical properties used by the SpaMTP indexed MS1 annotation engine.",
        tags = "SpaMTPdb:RaMP:Metabolomics:MassSpectrometry"
    ),
    source_df = list(
        description = "RaMP stable source-identifier mappings, names, provenance and pathway counts.",
        tags = "SpaMTPdb:RaMP:Identifiers"
    ),
    analyte = list(
        description = "Pruned RaMP analyte identifiers and analyte types.",
        tags = "SpaMTPdb:RaMP:Identifiers"
    ),
    analytehaspathway = list(
        description = "RaMP analyte-to-pathway relationships used by SpaMTP enrichment analyses.",
        tags = "SpaMTPdb:RaMP:Pathways"
    ),
    pathway = list(
        description = "RaMP pathway identifiers, sources, types, categories and names.",
        tags = "SpaMTPdb:RaMP:Pathways"
    ),
    ramp_db_metadata = list(
        description = "Version, provenance, pruning and graph-harmonisation metadata for the SpaMTP RaMP snapshot.",
        tags = "SpaMTPdb:RaMP:Provenance"
    ),
    ramp_hmdb = list(
        description = "HMDB pathway topology harmonised to RaMP 3.0.7 compound identifiers.",
        tags = "SpaMTPdb:RaMP:HMDB:Pathways"
    ),
    ramp_kegg = list(
        description = "KEGG pathway topology harmonised to RaMP 3.0.7 compound identifiers.",
        tags = "SpaMTPdb:RaMP:KEGG:Pathways"
    ),
    ramp_reactome = list(
        description = "Reactome pathway topology harmonised to RaMP 3.0.7 compound identifiers.",
        tags = "SpaMTPdb:RaMP:Reactome:Pathways"
    ),
    ramp_wikipathway = list(
        description = "WikiPathways topology harmonised to RaMP 3.0.7 compound identifiers.",
        tags = "SpaMTPdb:RaMP:WikiPathways:Pathways"
    ),
    hmdb_db = list(
        description = "Legacy SpaMTP cleaned HMDB metabolite reference table.",
        source_type = "CSV", source_url = "https://hmdb.ca/",
        source_version = "5.0", data_provider = "HMDB and SpaMTP",
        tags = "SpaMTPdb:HMDB:Legacy"
    ),
    chebi_db = list(
        description = "Legacy SpaMTP cleaned ChEBI metabolite reference table.",
        source_type = "CSV", source_url = "https://www.ebi.ac.uk/chebi/",
        source_version = "236", data_provider = "ChEBI and SpaMTP",
        tags = "SpaMTPdb:ChEBI:Legacy"
    ),
    lipidmaps_db = list(
        description = "Legacy SpaMTP cleaned LIPID MAPS metabolite reference table.",
        source_type = "CSV", source_url = "https://www.lipidmaps.org/",
        source_version = "2024-08-19", data_provider = "LIPID MAPS and SpaMTP",
        tags = "SpaMTPdb:LIPIDMAPS:Legacy"
    ),
    gnps_db = list(
        description = "Legacy SpaMTP cleaned GNPS metabolite reference table.",
        source_type = "CSV", source_url = "https://gnps.ucsd.edu/",
        source_version = "SpaMTP snapshot", data_provider = "GNPS and SpaMTP",
        tags = "SpaMTPdb:GNPS:Legacy"
    ),
    filtered_fmp10 = list(
        description = "Curated FMP10 matrix-associated metabolite mappings retained for legacy workflows.",
        source_type = "CSV",
        source_url = "https://github.com/GenomicsMachineLearning/SpaMTP",
        source_version = "SpaMTP 1.1", data_provider = "SpaMTP",
        tags = "SpaMTPdb:FMP10:MALDI:Legacy"
    ),
    smiles_features = list(
        description = paste(
            "Precomputed functional groups, proposed ionisation sites, and",
            "positive-, negative-, neutral-, and alkali-adduct priors derived",
            "from unique RaMP SMILES."
        ),
        tags = "SpaMTPdb:RaMP:SMILES:Metabolomics:MassSpectrometry"
    )
)

manifest_path <- file.path(
    package_root, "inst", "manifest", "resource_manifest.csv"
)
metadata_path <- file.path(package_root, "inst", "extdata", "metadata.csv")

if (!validate_only) {
    manifest <- utils::read.csv(
        manifest_path, stringsAsFactors = FALSE, check.names = FALSE
    )
    missing <- setdiff(manifest$resource, names(annotations))
    if (length(missing)) {
        stop(
            "No Hub annotation defined for: ", paste(missing, collapse = ", "),
            call. = FALSE
        )
    }
    if (any(grepl("^s3://", manifest$location_prefix))) {
        stop(
            "The manifest still points at the Bioconductor S3 bucket. ",
            "Re-run stage_resources.R with the Zenodo record ID.",
            call. = FALSE
        )
    }

    field <- function(resource, name, default) {
        value <- annotations[[resource]][[name]]
        if (is.null(value)) default else value
    }

    metadata <- data.frame(
        Title = manifest$title,
        Description = vapply(
            manifest$resource, field, character(1), "description", NA_character_
        ),
        BiocVersion = bioc_version,
        Genome = NA_character_,
        SourceType = vapply(
            manifest$resource, field, character(1), "source_type", "MySQL"
        ),
        SourceUrl = vapply(
            manifest$resource, field, character(1), "source_url",
            "https://github.com/ncats/RaMP-DB"
        ),
        SourceVersion = vapply(
            manifest$resource, field, character(1), "source_version", "3.0.7"
        ),
        Species = NA_character_,
        TaxonomyId = NA_character_,
        Coordinate_1_based = NA,
        DataProvider = vapply(
            manifest$resource, field, character(1), "data_provider",
            "NCATS RaMP-DB and SpaMTP"
        ),
        Maintainer = "Tianyao Lu <lu.t@wehi.edu.au>",
        RDataClass = manifest$r_data_class,
        DispatchClass = manifest$dispatch_class,
        Location_Prefix = manifest$location_prefix,
        RDataPath = manifest$rdata_path,
        Tags = vapply(manifest$resource, field, character(1), "tags", NA_character_),
        stringsAsFactors = FALSE,
        check.names = FALSE
    )
    rownames(metadata) <- NULL
    utils::write.csv(metadata, metadata_path, row.names = FALSE, na = "")
    message("Wrote ", metadata_path, " (", nrow(metadata), " resources).")
}

if (!requireNamespace("AnnotationHubData", quietly = TRUE)) {
    stop("Install AnnotationHubData before validating Hub metadata.", call. = FALSE)
}
AnnotationHubData::makeAnnotationHubMetadata(package_root, fileName = "metadata.csv")
message("makeAnnotationHubMetadata() validated ", metadata_path, ".")
