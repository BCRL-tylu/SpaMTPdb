interaction_utils <- function() {
    path <- system.file("scripts", "pathway_interaction_utils.R", package = "SpaMTPdb")
    skip_if_not(file.exists(path), "Maintainer source utilities are not installed")
    env <- new.env(parent = globalenv())
    sys.source(path, envir = env)
    env
}

test_that("conversion preserves every interaction and direction, independent of factor levels", {
    util <- interaction_utils()
    edge <- data.frame(
        src_type = "ENTREZID", src = c("1", "1", "2"),
        dest_type = "ENTREZID", dest = c("2", "3", "3"),
        direction = factor(c("directed", "undirected", "directed"),
            levels = c("undirected", "directed")
        ),
        type = factor(c("Process(inhibition)", "Process(activation)", "Process(phosphorylation)"),
            levels = c("Process(phosphorylation)", "Process(inhibition)", "Process(activation)")
        )
    )
    identifiers <- list2env(list(
        "entrez:1" = "RAMP_G_1", "entrez:2" = "RAMP_G_2",
        "entrez:3" = "RAMP_G_3"
    ), parent = emptyenv())
    result <- util$.pi_convert_edges(edge, identifiers)
    expect_identical(result$reaction_type, c(4L, 6L, 5L))
    expect_identical(result$directed, c(1L, 2L, 1L))
    expect_identical(result$source_reaction_type, as.character(edge$type))
    expect_identical(result$src, c("RAMP_G_1", "RAMP_G_1", "RAMP_G_2"))
    expect_identical(result$dest, c("RAMP_G_2", "RAMP_G_3", "RAMP_G_3"))
    empty <- util$.pi_convert_edges(edge[FALSE, ], identifiers)
    expect_true(all(is.na(empty)))
})

test_that("database-specific labels share style codes without confusing activation and inhibition", {
    util <- interaction_utils()
    expect_identical(util$.pi_reaction_codes(c(
        "Binding", "Control(In: ACTIVATION of BiochemicalReaction)",
        "Control(Out: INHIBITION of BiochemicalReaction)", "Process(BiochemicalReaction)",
        "Control(indirect)"
    )), c(2L, 6L, 4L, 16L, 1L))
    expect_error(util$.pi_reaction_codes("new unrecognised interaction"), "Unmapped source")
    expect_error(util$.pi_direction_codes("new direction"), "Unknown source")
})

test_that("corrections restore collapsed parallel interactions and leave other resources untouched", {
    value <- list(list(id = "hsa:04110", protEdges = data.frame(
        src = "RAMP_G_1", dest = "RAMP_G_2", directed = 1L, reaction_type = 4L
    )))
    patch <- list(
        input_sha256 = SpaMTPdb:::.spamtpdb_graph_fingerprint(value),
        provenance = list(repair = "fixture"),
        pathways = list(list(protEdges = list(
            rows = c(1L, 1L), directed = c(1L, 2L), reaction_type = c(4L, 6L),
            source_reaction_type = c("Process(inhibition)", "Process(activation)")
        )))
    )
    attr(value, "spamtp_database") <- list(version = "3.0.7")
    result <- SpaMTPdb:::.spamtpdb_apply_interaction_patch(value, patch)
    expect_identical(result[[1]]$protEdges$reaction_type, c(4L, 6L))
    expect_identical(result[[1]]$protEdges$src, rep("RAMP_G_1", 2))
    expect_identical(attr(result, "spamtp_database"), attr(value, "spamtp_database"))
    expect_identical(SpaMTPdb:::.spamtpdb_apply_interaction_patch(result, patch), result)
    modified <- value
    modified[[1]]$protEdges$dest <- "CUSTOM"
    expect_identical(SpaMTPdb:::.spamtpdb_apply_interaction_patch(modified, patch), modified)
})

test_that("the Cell Cycle correction recovers every archived source label offline", {
    fixture <- readRDS(testthat::test_path("fixtures", "cell_cycle_interactions.rds"))
    patch <- readRDS(system.file("extdata", "ramp_kegg_interactions_v1.rds", package = "SpaMTPdb"))
    # Exercise the real correction on a small, unmodified excerpt. The staged
    # resource test below separately verifies the full-resource fingerprint.
    value <- list(fixture$legacy_topology)
    patch$input_sha256 <- SpaMTPdb:::.spamtpdb_graph_fingerprint(value)
    patch$pathways <- patch$pathways[fixture$pathway_index]
    fixed <- SpaMTPdb:::.spamtpdb_apply_interaction_patch(value, patch)[[1L]]
    expect_true(all(fixture$legacy_topology$protEdges$reaction_type == 4L))
    expect_identical(fixed$protEdges$source_reaction_type, fixture$source_reaction_type)
    expect_identical(
        fixed$protEdges$directed,
        match(fixture$source_direction, c("directed", "undirected"))
    )
    expect_length(unique(fixed$protEdges$reaction_type), 11L)
    expect_equal(sum(fixed$protEdges$reaction_type == 4L), 286L)
    expect_equal(sum(fixed$protEdges$reaction_type == 6L), 113L)
})

