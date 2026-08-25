# SpaMTPdb 0.99.1

* Version bump only. The Zenodo download fallback shipped inside 0.99.0, so an
  installation cached by version alone could still hold the pre-Zenodo build
  that failed with "AnnotationHub does not yet contain ...". Bumping the version
  lets those caches invalidate.

# SpaMTPdb 0.99.0

* Initial Bioconductor submission scaffold.
* Added versioned AnnotationHub metadata for RaMP 3.0.7 and legacy metabolite
  annotation resources.
* Resource files are published on Zenodo rather than in the Bioconductor Hub
  bucket, which no longer accepts data from external contributors. Hub records
  point at the Zenodo copy through `Location_Prefix` and `RDataPath`.
* Added a verified download and cache path so a resource can be retrieved from
  its immutable Zenodo URL before the AnnotationHub records are published.
  Downloads are checked against the recorded size and MD5 checksum.
* Added `inst/scripts/zenodo_upload.R` to deposit staged resources on Zenodo,
  and taught `inst/scripts/stage_resources.R` and `inst/scripts/make-metadata.R`
  to regenerate the manifest and Hub metadata from a Zenodo record ID.
* Moved `resource_manifest.csv` out of `inst/extdata`, because
  `AnnotationHubData::makeAnnotationHubMetadata()` reads every CSV in that
  directory as Hub metadata.
* Recorded RaMP-derived resources with `SourceType: MySQL`; the Hub controlled
  vocabulary has no SQLite term.
* Added local-resource support for development before Hub ingestion.
* Added an independent, precomputed `smiles_features` resource for functional
  groups and positive-, negative-, neutral-, and alkali-adduct priors.
