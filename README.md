# SpaMTPdb

`SpaMTPdb` is the versioned annotation-data companion to
[`SpaMTP`](https://github.com/SpaMTP-project/SpaMTP). It keeps large
RaMP/MS1/pathway resources outside the SpaMTP software package and retrieves
them through Bioconductor AnnotationHub or their verified immutable source URLs.
`SpaMTPData` supplies experiment data; SpaMTP supplies analysis and explicit
container conversion. Neither data package depends on the SpaMTP software
package, avoiding a circular runtime dependency.

The annotation and experiment interfaces can share one Zenodo version family.
SpaMTPdb's maintainer recipes coordinate the physical resource publication;
SpaMTPData continues to own experiment metadata, documentation and reading.
Sharing storage does not put experiment RDS into the SpaMTPdb installation,
its default database bundle, or its AnnotationHub registry.

The coordinated API uses camelCase: `spaMTPdbResource()`, `spaMTPdbResources()`,
`spaMTPdbBundle()` and `spaMTPdbVersion()`. Install SpaMTPdb >= 0.99.2 with
SpaMTP >= 0.99.3; the former PascalCase exports have been removed on the
submission API. Resource versions (for example RaMP 3.0.7) are independent of
R package versions and have not changed in this update.

During development, staged resources can be used without network access:

```r
options(SpaMTPdb.resource_dir = "/path/to/SpaMTPdb-resources/3.0.7")
chem_props <- SpaMTPdb::spaMTPdbResource("chem_props", offline = TRUE)
```

The default release is the pruned RaMP 3.0.7 snapshot. Each table and topology
is a separate resource, so an MS1 annotation does not download pathway graphs
and a KEGG network does not load HMDB topology data.

Local files and cached downloads are checked against the manifest's size and
MD5. `offline = TRUE` can reuse the verified cache without contacting a Hub.
Use `verify = FALSE` only for intentional development fixtures; altered files
must not be presented as an unchanged official resource version.

For a new resource version, run the current annotation engine against a staged
chemical table. The script refuses to overwrite an existing structure table:

```sh
Rscript inst/scripts/precompute_smiles_features.R \
  ../SpaMTP-bioc-main /path/to/new-resource-staging NEW_VERSION 8 10000
```

`smiles_features` is a separate optional resource whose `smiles` column matches
`chem_props$iso_smiles`. This
keeps the pruned `chem_props` table compact while allowing SpaMTP's annotation
engine to attach precomputed functional groups and ion-mode priors on demand.

The staged files are ready for an immutable host approved by AnnotationHub.
They are deliberately excluded from Git.

`stage_resources.R` can describe an existing staging directory. If original
`.rda` files are needed, pass an archival checkout explicitly: the Bioconductor
software package no longer bundles database tables. Publishing a new resource
version and updating its Hub metadata are separate maintainer actions; this
API migration does not republish or rewrite the existing Zenodo files.

## Shared resource publication

Use SpaMTPdb and SpaMTPData >= 0.99.3 for the shared publication recipes.
The base snapshot is record 22045311 (RaMP 3.0.7), in version family 22045310.
`inst/manifest/shared_record.json` records that family and proposed collection
metadata. Collection versions (for example `2026.09`), database versions
(`3.0.7`) and experiment versions (`1.1.0`) are independent.

The shared collection `2026.09` is published as
[record 22733262](https://zenodo.org/records/22733262), containing the 16 database
files and seven native SpatialExperiment files. SpaMTPData >= 0.99.4 provides
the native experiment registry. SpaMTPdb's unchanged 3.0.7 registry continues
to use the original 22045311 snapshot; sharing storage does not mix the two
runtime interfaces or imply completed Hub ingestion.

Prepare from the verified database files and the native outputs of SpaMTPData's
one-time conversion recipe. The output must be a new or empty staging directory:

```sh
Rscript inst/scripts/prepare-shared-release.R \
  /path/to/database/3.0.7 /path/to/native/1.1.0 \
  /path/to/SpaMTPData /path/to/shared-staging 2026.09
Rscript inst/scripts/zenodo_upload.R /path/to/shared-staging
```

This produces a public resource manifest and provenance supplements, a proposed
Zenodo metadata body, and an exact local upload whitelist. The large RDS stay
at their verified source paths. No runtime registry is changed. The second
command performs an offline dry run, without credentials or network access.

After reviewing the proposed title, creator order, provenance and licences,
either create a new-version draft on the existing Zenodo page and use
`--draft-id ID --upload`, or explicitly request `--create-version --upload`.
Set `ZENODO_TOKEN` only in the local environment; do not put it in scripts,
logs or Git. Existing drafts need `deposit:write`; the new-version API also
needs `deposit:actions`. No script calls the publication endpoint.

```sh
Rscript inst/scripts/zenodo_upload.R /path/to/shared-staging --draft-id ID --upload
# Interrupted transfers resume the saved draft and skip checksum-matching files:
Rscript inst/scripts/zenodo_upload.R /path/to/shared-staging --upload
```

The uploader checks the family and refuses published records, unknown files,
conflicting bytes and unrelated drafts. It never deletes files or overwrites
conflicts. It no longer accepts the old `resource_dir version --publish` syntax.
The original 22045311 snapshot and SpaMTPdb's 3.0.7 registry retain their URLs.

After manual publication, SpaMTPData's `inst/scripts/register-native-release.R`
verifies the public files and generates candidate ExperimentHub/registry tables.
Review those tables before applying them and requesting Hub ingestion. A public
Zenodo release is not evidence of completed Hub registration.

If you use these resources, cite the SpaMTP paper:
[Causer, Lu, Kriel *et al.*, Nature Methods (2026)](https://doi.org/10.1038/s41592-026-03140-8).
