# SpaMTPdb

**SpaMTPdb** provides versioned annotation resources for
[SpaMTP](https://bioconductor.org/packages/SpaMTP/): RaMP metabolite and pathway
tables, pathway topology, precomputed SMILES features, and a human gene
identifier reference from HGNC. Resources are downloaded on demand and cached
locally. Companion experimental datasets are provided separately by
[SpaMTPData](https://bioconductor.org/packages/SpaMTPData/).

RaMP resource versions, HGNC archive versions and R package versions are
independent. Pin the resource version used by each analysis.

## Installation

To install `SpaMTPdb` from Bioconductor, start R (>= 4.6.0) and enter:

```r
if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")

BiocManager::install("SpaMTPdb")
```

Installing `SpaMTP` from Bioconductor installs `SpaMTPdb` automatically; run the
command above when using `SpaMTPdb` standalone.

## Quick start

```r
library(SpaMTPdb)

# Inspect available RaMP resources without downloading data.
spaMTPdbVersion()
spaMTPdbResources()[, c("resource", "version", "category")]

# Download and cache the resources needed for an analysis.
chem_props <- spaMTPdbResource("chem_props", version = "3.0.7")
genes <- spaMTPdbGeneReference(version = "2026.7.7")
```

Use `metadata = TRUE` in either retrieval function to inspect a resource
without downloading it. Use `offline = TRUE` to read previously cached or
locally staged files. The retrieval examples above download data on first use.

RaMP resources are retrieved through AnnotationHub when available, with a
Zenodo fallback; the HGNC reference uses a fixed archive. Direct downloads are
verified against the file sizes and checksums recorded in the package manifest.

See the [vignette](vignettes/SpaMTPdb.Rmd) (`browseVignettes("SpaMTPdb")`) for
resource bundles, local directories and cache configuration. Post usage
questions on the [Bioconductor Support Site](https://support.bioconductor.org/)
and report bugs in the
[GitHub issue tracker](https://github.com/BCRL-tylu/SpaMTPdb/issues).

## Citation

Causer, Lu, Kriel *et al.* (2026).
[SpaMTP: integrative statistical analysis and visualization of spatial
metabolomics and transcriptomics data](https://doi.org/10.1038/s41592-026-03140-8).
*Nature Methods*, 23, 1501–1506.
