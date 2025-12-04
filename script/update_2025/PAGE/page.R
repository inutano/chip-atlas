suppressPackageStartupMessages(library("data.table"))
suppressPackageStartupMessages(library("dplyr"))
suppressPackageStartupMessages(library("DESeq2"))

args <- commandArgs(trailingOnly = TRUE) %>% as.character()
count_path <- args[1]
grn_dir <- args[2]
grn_name <- args[3]
output_path <- args[4]


# /home/okishinya/zou/miniconda3/envs/r420/bin/Rscript
# count_path <- "/home/okishinya/chipatlas/analTools/PAGE/examples/human.tsv"
# grn_dir <- "/home/okishinya/chipatlas/results/hg38/page/grn/1000"
# grn_name <- "ATC.ALL.05.AllAg.AllCell.1000.1000.grn"
# output_path <- "/home/zou/chipatlas_analtools/page_stats"

count_table <- fread(count_path, sep = "\t", header = TRUE) %>%
  setnames(1, "Gene") %>%
  as.data.frame() %>%
  aggregate(. ~ Gene, data = ., FUN = sum) %>%
  tibble::column_to_rownames("Gene") %>%
  as.matrix() %>%
  .[rowSums(.) > 0, ]

# calc log2fc, mean, sd
groups_vector <- gsub("_[0-9]+$", "", colnames(count_table))
contrast <- c("con", unique(groups_vector))
group <- data.frame(con = factor(groups_vector))

result <- DESeqDataSetFromMatrix(
  countData = count_table, colData = group, design = ~con
) %>%
  DESeq(quiet = TRUE) %>%
  results(contrast)

all_l2fc <- setNames(result$log2FoldChange, rownames(result))
num_all_genes <- length(all_l2fc)
mu <- mean(all_l2fc)
delta <- sd(all_l2fc)


grn_list <- list.files(
  grn_dir,
  pattern = glob2rx(paste0(grn_name, ".*")),
  full.names = TRUE
)

# initialize result df
final_result_df <- data.frame(
  srx = character(),
  gs_size = character(),
  mean_l2fc = character(),
  log_p = numeric(),
  log_q = numeric(),
  z_score = numeric()
)

for (grn in grn_list) {
  message(paste0(
    "[DEBUG] <page.r> ",
    match(grn, grn_list), "/", length(grn_list), ": ", grn
  ))
  gene_set_list <- suppressMessages(
    fread(grn, col.names = c("srx", "gene"), sep = "\t")
  ) %>%
    mutate(
      srx = as.factor(srx),
      gene = as.factor(gene)
    ) %>%
    group_by(srx) %>%
    summarize(genes = list(unique(gene))) %>%
    pull(genes, srx)

  gene_set_info <- rbindlist(Map(function(gs) {
    ix <- match(gs, names(all_l2fc)) %>%
      na.omit() %>%
      as.vector()
    data.table(
      mean_l2fc = mean(all_l2fc[ix], na.rm = TRUE),
      gs_size = length(ix)
    )
  }, gene_set_list))

  gene_set_info <- gene_set_info[, srx := names(gene_set_list)] %>%
    filter(gs_size > 0)
  rm(gene_set_list)

  # # release memory
  # if (match(grn, grn_list) %% 5 == 0) invisible(replicate(2, gc()))

  # PAGE
  z_score <- (gene_set_info$mean_l2fc - mu) *
    sqrt(gene_set_info$gs_size) / delta

  results_df <- data.frame(
    srx = gene_set_info$srx,
    gs_size = paste0(gene_set_info$gs_size, "/", num_all_genes),
    mean_l2fc = paste0(
      sprintf("%.2f", gene_set_info$mean_l2fc),
      "/",
      sprintf("%.2f", mu)
    ),
    log_p = rep(0, nrow(gene_set_info)),
    log_q = rep(0, nrow(gene_set_info)),
    z_score = z_score
  )

  final_result_df <- rbind(final_result_df, results_df)
}

pp <- 2 * pnorm(abs(final_result_df$z_score), lower.tail = FALSE)
qq <- p.adjust(pp, method = "BH")

final_result_df$log_p <- ifelse(pp == 0, -324, log10(pp))
final_result_df$log_q <- ifelse(qq == 0, -324, log10(qq))

#final_result_df$log_p <- log10(
#  2 * pnorm(
#    abs(final_result_df$z_score),
#    lower.tail = FALSE
#  )
#)
#final_result_df$log_q <- log10(
#  p.adjust(
#    10^final_result_df$log_p,
#    method = "BH"
#  )
#)

fwrite(final_result_df, output_path, sep = "\t", col.names = FALSE)
