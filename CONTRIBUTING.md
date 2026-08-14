# Contributing to SpaMTPdb

Database changes must be reproducible and versioned. Open an issue before
changing an existing release, and create a new resource version when upstream
RaMP content or pruning rules change.

For a database update:

1. Record upstream source versions and pruning rules.
2. Run `inst/scripts/stage_resources.R` against a SpaMTP source checkout.
3. Verify dimensions, classes, MD5 checksums, and cross-table RaMP IDs.
4. Upload immutable resource files to the approved Bioconductor data host.
5. Update both resource and AnnotationHub metadata.
6. Run `R CMD check` and `BiocCheck::BiocCheck()` before opening a pull request.

Do not commit generated `.rds` resources or credentials to Git.
