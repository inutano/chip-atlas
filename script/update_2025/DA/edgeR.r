suppressPackageStartupMessages(library(edgeR))
suppressPackageStartupMessages(library(magrittr))

args <- commandArgs(trailingOnly = TRUE) %>% as.character()
count_path <- args[1]
srx_a_path <- args[2]
srx_b_path <- args[3]
peak_path <- args[4]
output_bed_path <- args[5]

count <- read.csv(count_path, header = TRUE, row.names = 1) %>% as.matrix()
srx_a <- scan(srx_a_path, what = "", quiet = TRUE)
srx_b <- scan(srx_b_path, what = "", quiet = TRUE)
peak_bed <- read.table(
  peak_path,
  sep = "\t", header = FALSE, row.names = 4
)[, 1:3]

group <- ifelse(colnames(count) %in% srx_a, "A",
  ifelse(colnames(count) %in% srx_b, "B", NA)
) %>% factor()

edger_obj <- DGEList(counts = count, group = group)
keep <- filterByExpr(edger_obj, group = group)
edger_obj <- edger_obj[keep, , keep.lib.sizes = FALSE] %>% calcNormFactors()

invisible(
  apply(
    data.frame(
      ID = rownames(edger_obj$samples),
      Group = edger_obj$samples$group
    ),
    1,
    function(x) {
      cat("[INFO] <samples>", paste(x, collapse = " "), "\n")
    }
  )
)

edger_obj <- if (all(table(group) == 1)) {
  edger_obj %>%
    estimateGLMCommonDisp(method = "deviance", robust = TRUE, subset = NULL)
} else {
  edger_obj %>%
    estimateCommonDisp() %>%
    estimateTagwiseDisp()
}

format_counts <- function(df, collapse = FALSE) {
  apply(df, 1, function(row) {
    formatted <- formatC(row, format = "f", digits = 2)
    if (collapse) paste(formatted, collapse = ",") else formatted
  })
}

norm_count <- edger_obj %>%
  {
    if (all(table(group) == 1)) {
      cpm(., normalized.lib.sizes = TRUE)
    } else {
      .$pseudo.counts
    }
  } %>%
  .[, order(group)] %>%
  as.data.frame() %>%
  split.default(sort(group)) %>%
  lapply(format_counts, collapse = !all(table(group) == 1)) %>%
  as.data.frame()

result <- edger_obj %>%
  exactTest(pair = 2:1) %>%
  topTags(n = nrow(count)) %>%
  `[[`("table") %>%
  .[intersect(rownames(peak_bed), rownames(.)), c(1, 3, 4)] %>%
  {
    cbind(peak_bed[rownames(.), ], norm_count[rownames(.), ], .)
  }

write.table(
  result, output_bed_path,
  sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE
)
