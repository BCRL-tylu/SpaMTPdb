# SpaMTPdb

**SpaMTPdb** provides versioned annotation resources for
[SpaMTP](https://github.com/SpaMTP-project/SpaMTP): RaMP metabolite and pathway
tables, pathway topology, precomputed SMILES features, and a human gene
identifier reference from HGNC. Resources are downloaded as needed and cached
locally. Experimental datasets are provided separately by SpaMTPData.

RaMP resource versions, HGNC archive versions and R package versions are
independent. Pin the resource version used by each analysis.

## Installation

Requires **R >= 4.6.0**. During Bioconductor review, install from
[BiocStaging](https://github.com/BiocStaging/SpaMTPdb):

```r
options(timeout = max(600, getOption("timeout")))
Sys.setenv(R_DEFAULT_INTERNET_TIMEOUT = as.character(getOption("timeout")))

if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager", repos = "https://cloud.r-project.org")
if (!requireNamespace("remotes", quietly = TRUE))
    install.packages("remotes", repos = "https://cloud.r-project.org")

BiocManager::install("BiocStaging/SpaMTPdb@devel",
                     ask = FALSE, update = FALSE)
```

For the SpaMTP workflow, install this package before installing SpaMTP.

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

See the [vignette](vignettes/SpaMTPdb.Rmd) for resource bundles, local
directories and cache configuration.

## Citation

Causer, Lu, Kriel *et al.* (2026).
[SpaMTP: integrative statistical analysis and visualization of spatial
metabolomics and transcriptomics data](https://doi.org/10.1038/s41592-026-03140-8).
*Nature Methods*, 23, 1501–1506.
