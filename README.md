# SpaMTPdb

`SpaMTPdb` is the versioned annotation-data companion to
[`SpaMTP`](https://github.com/GenomicsMachineLearning/SpaMTP). It keeps large
RaMP/MS1/pathway resources outside the SpaMTP software package and retrieves
them through Bioconductor AnnotationHub.

During development, staged resources can be used without network access:

```r
options(SpaMTPdb.resource_dir = "/path/to/SpaMTPdb-resources/3.0.7")
chem_props <- SpaMTPdb::SpaMTPdbResource("chem_props")
```

The default release is the pruned RaMP 3.0.7 snapshot. Each table and topology
is a separate resource, so an MS1 annotation does not download pathway graphs
and a KEGG network does not load HMDB topology data.

To regenerate a release from a SpaMTP checkout:

```sh
Rscript inst/scripts/stage_resources.R ../SpaMTP ../SpaMTPdb-resources 3.0.7
Rscript inst/scripts/make-metadata.R
```

The staged files are ready for an immutable host approved by AnnotationHub.
They are deliberately excluded from Git.

If you use these resources, cite the SpaMTP paper:
[Causer, Lu, Kriel *et al.*, Nature Methods (2026)](https://doi.org/10.1038/s41592-026-03140-8).
