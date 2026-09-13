test_that("every Imports dependency has explicit namespace imports", {
    declared <- utils::packageDescription("SpaMTPdb", fields = "Imports")
    dependencies <- trimws(gsub("\\s*\\([^)]*\\)", "",
        strsplit(declared, ",")[[1L]]))
    imports <- getNamespaceImports("SpaMTPdb")

    expect_true(all(dependencies %in% names(imports)))
    for (dependency in dependencies) {
        symbols <- imports[[dependency]]
        expect_type(symbols, "character")
        expect_gt(length(symbols), 0L)
    }
})
