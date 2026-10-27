# Contributing to SpaMTPdb

Keep resource updates reproducible and versioned. Published RaMP and HGNC
snapshots have fixed locations and checksums; changes to upstream content or
pruning rules require a new resource version.

## Resource ownership

* `inst/manifest/resource_manifest.csv` describes RaMP-derived annotation
  resources; `inst/extdata/metadata.csv` describes their AnnotationHub records.
* `inst/manifest/gene_reference_manifest.csv` describes fixed human HGNC
  archives, with versions independent of RaMP.
* SpaMTPData owns experimental resources and their ExperimentHub metadata.
  A shared Zenodo collection does not combine the two registries.

## Preparing a resource update

1. Record the upstream versions, licences, pruning rules and source checksums.
2. Stage files outside the package or under ignored `data-raw/staging/`.
   `inst/scripts/stage_resources.R` reads an explicitly supplied archival
   SpaMTP checkout containing the original `data/*.rda` objects, or an already
   populated staging directory. The current software package does not bundle
   these database objects.
3. Verify object classes, dimensions, cross-table identifiers, file sizes and
   MD5 checksums. Keep the existing RaMP 3.0.7 snapshot unchanged.
4. For a shared collection, use `inst/scripts/prepare-shared-release.R` to
   prepare the resource manifest, provenance and upload plan. It does not
   change the published registries.
5. Validate the prepared payload locally:

   ```sh
   Rscript inst/scripts/upload-shared-release.R /path/to/staging
   ```

   The default is an offline dry run. A maintainer may then explicitly select
   a new version or an existing draft and upload the verified plan. The script
   leaves publication as a separate action. Resource files are hosted on
   Zenodo; the package's Hub metadata points to those external files.
6. After publication, register new resources with their immutable published
   URLs, then regenerate and validate Hub metadata with
   `inst/scripts/make-metadata.R`. Do not repoint an existing resource version
   to a later collection record.

## Package changes and local files

Run `R CMD build`, `R CMD check` and `BiocCheck::BiocCheck()` for the package.
Keep logs, check directories and source archives outside the checkout or in
`.local/`. Git and package-build ignore rules exclude these generated files;
maintained scripts, tests, manifests and documentation remain reviewable.
Do not commit generated resource files or credentials.
