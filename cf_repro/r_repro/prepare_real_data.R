# prepare_real_data.R  —  Download and preprocess real datasets (run once offline)
#
# Usage: Rscript prepare_real_data.R
#
# Output (saved to results/real/):
#   hillstrom_raw.rds  —  list(men, women, X_cols, Y_options)
#   lenta_raw.rds      —  preprocessed data.frame (100K subsample)
#   criteo_raw.rds     —  preprocessed data.frame (100K subsample)

options(timeout = 600)   # allow large downloads (default 60s is too short for Criteo)

sd_path <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")
OUT_DIR  <- file.path(sd_path, "..", "results", "real")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== prepare_real_data.R ===\n")
cat(sprintf("Output directory: %s\n\n", normalizePath(OUT_DIR)))

# ── helpers ───────────────────────────────────────────────────────────────────

safe_download <- function(url, dest, label) {
  cat(sprintf("Downloading %s from:\n  %s\n", label, url))
  tryCatch({
    download.file(url, dest, mode = "wb", quiet = FALSE)
    cat(sprintf("  -> saved to %s\n", dest))
    TRUE
  }, error = function(e) {
    cat(sprintf("  -> FAILED: %s\n", conditionMessage(e)))
    FALSE
  })
}

stratified_sample <- function(df, strat_col, n, seed = 42) {
  set.seed(seed)
  groups  <- split(seq_len(nrow(df)), df[[strat_col]])
  props   <- sapply(groups, length) / nrow(df)
  sizes   <- pmax(1L, round(props * n))
  idx     <- unlist(mapply(function(g, s) g[sample(length(g), min(s, length(g)))],
                           groups, sizes, SIMPLIFY = FALSE))
  df[sort(idx), ]
}

# ── 1. Hillstrom MineThatData ─────────────────────────────────────────────────

prepare_hillstrom <- function(out_dir) {
  dest <- file.path(out_dir, "hillstrom_raw.rds")
  if (file.exists(dest)) {
    cat("[Hillstrom] Already exists, skipping.\n\n"); return(invisible(TRUE))
  }
  cat("[Hillstrom] Downloading...\n")
  url <- paste0("http://www.minethatdata.com/",
                "Kevin_Hillstrom_MineThatData_E-MailAnalytics_DataMiningChallenge_2008.03.20.csv")
  tmp <- tempfile(fileext = ".csv")
  ok  <- safe_download(url, tmp, "Hillstrom")
  if (!ok) {
    cat("[Hillstrom] FAILED. Place the CSV manually at:\n")
    cat(sprintf("  %s/hillstrom_raw.csv\n", out_dir))
    cat("  Then re-run this script.\n\n")
    return(invisible(FALSE))
  }
  raw <- read.csv(tmp)
  # encode categorical features
  raw$zip_code_enc <- as.integer(factor(raw$zip_code,
                        levels = c("Rural", "Suburban", "Urban")))
  raw$channel_enc  <- as.integer(factor(raw$channel,
                        levels = c("Phone", "Web", "Multichannel")))
  X_cols <- c("recency", "history", "mens", "womens",
               "zip_code_enc", "newbie", "channel_enc")
  # split into two binary treatment analyses
  df_men <- raw[raw$segment %in% c("No E-Mail", "Mens E-Mail"), ]
  df_men$W <- as.integer(df_men$segment == "Mens E-Mail")
  df_women <- raw[raw$segment %in% c("No E-Mail", "Womens E-Mail"), ]
  df_women$W <- as.integer(df_women$segment == "Womens E-Mail")
  saveRDS(list(men    = df_men,
               women  = df_women,
               X_cols = X_cols,
               Y_options = c("visit", "conversion", "spend")),
          dest)
  cat(sprintf("[Hillstrom] Saved. men: %d rows, women: %d rows\n\n",
              nrow(df_men), nrow(df_women)))
  invisible(TRUE)
}

# ── 2. Lenta ──────────────────────────────────────────────────────────────────

prepare_lenta <- function(out_dir) {
  dest <- file.path(out_dir, "lenta_raw.rds")
  if (file.exists(dest)) {
    cat("[Lenta] Already exists, skipping.\n\n"); return(invisible(TRUE))
  }
  # Try multiple public mirrors in order
  lenta_urls <- list(
    list(url  = "https://sklift.s3.eu-west-2.amazonaws.com/lenta_dataset.csv.gz",
         gz   = TRUE,  label = "Lenta (sklift S3 eu-west-2 gz)"),
    list(url  = "https://huggingface.co/datasets/mstz/lenta/resolve/main/data/lenta_dataset.csv",
         gz   = FALSE, label = "Lenta (HuggingFace)"),
    list(url  = "https://raw.githubusercontent.com/catboost/tutorials/master/competition_examples/RetailHero/data/uplift_train.csv",
         gz   = FALSE, label = "Lenta (CatBoost tutorials)")
  )
  ok  <- FALSE
  tmp <- NULL
  for (m in lenta_urls) {
    t <- tempfile(fileext = if (m$gz) ".csv.gz" else ".csv")
    if (safe_download(m$url, t, m$label)) {
      tmp <- if (m$gz) gzfile(t) else t
      ok  <- TRUE
      break
    }
  }

  if (!ok) {
    cat("[Lenta] All downloads failed.\n")
    cat("  Manual steps:\n")
    cat("  1. Download 'lenta_dataset.csv' from Kaggle:\n")
    cat("     https://www.kaggle.com/datasets/prashant111/lenta-dataset\n")
    cat(sprintf("  2. Place it at: %s/lenta_raw.csv\n", out_dir))
    cat("  3. Re-run this script — it will detect the CSV automatically.\n\n")

    # Try manual CSV fallback
    manual_csv <- file.path(out_dir, "lenta_raw.csv")
    if (!file.exists(manual_csv)) return(invisible(FALSE))
    cat("[Lenta] Found manual CSV, loading...\n")
    tmp <- manual_csv
  }

  cat("[Lenta] Loading CSV (may take a moment)...\n")
  df <- tryCatch(read.csv(tmp), error = function(e) {
    cat(sprintf("[Lenta] Read error: %s\n", conditionMessage(e))); NULL
  })
  if (is.null(df)) return(invisible(FALSE))

  # Detect W column (treatment) — handle both numeric 0/1 and "test"/"control"
  W_col <- if ("treatment" %in% names(df)) "treatment" else
            if ("group"     %in% names(df)) "group"     else
            names(df)[which(sapply(df, function(x) length(unique(x[!is.na(x)])) == 2))[1]]
  # Detect Y column (response)
  Y_col <- if ("response_att" %in% names(df)) "response_att" else
            if ("target"      %in% names(df)) "target"       else
            names(df)[which(names(df) != W_col & sapply(df, is.numeric))[1]]

  cat(sprintf("[Lenta] W column: %s, Y column: %s\n", W_col, Y_col))

  # Encode W: handle "test"/"control" string values → 1/0
  w_raw <- df[[W_col]]
  if (is.character(w_raw) || is.factor(w_raw)) {
    vals <- unique(w_raw[!is.na(w_raw)])
    treat_val <- vals[vals %in% c("test","treatment","treated","1","yes","True")][1]
    if (is.na(treat_val)) treat_val <- vals[1]
    df$W <- as.integer(w_raw == treat_val)
    cat(sprintf("[Lenta] Encoding W: '%s' → 1, rest → 0\n", treat_val))
  } else {
    df$W <- as.integer(w_raw)
  }
  df$Y <- as.numeric(df[[Y_col]])

  # drop rows with NA in W or Y
  df <- df[!is.na(df$W) & !is.na(df$Y), ]

  # Label-encode low-cardinality character columns (e.g. gender "Ж"/"М" → 1/2)
  char_cols <- names(df)[sapply(df, function(x) is.character(x) || is.factor(x))]
  char_cols <- setdiff(char_cols, c(W_col, "W"))
  for (cc in char_cols) {
    if (length(unique(df[[cc]])) <= 20)
      df[[cc]] <- as.integer(factor(df[[cc]]))
    else
      df[[cc]] <- NULL   # drop high-cardinality string columns
  }

  # X columns: numeric only, low-NA (≤10%), not W/Y/id
  all_num <- names(df)[sapply(df, is.numeric)]
  id_like  <- names(df)[sapply(df, function(x) length(unique(x)) == nrow(df))]
  na_pct   <- sapply(all_num, function(cn) mean(is.na(df[[cn]])))
  X_cols   <- setdiff(all_num[na_pct <= 0.10], c(W_col, Y_col, "W", "Y", id_like))
  cat(sprintf("[Lenta] X columns selected (≤10%% NA): %d\n", length(X_cols)))

  # subsample 100K stratified by W
  n_sub <- min(100000L, nrow(df))
  df_sub <- stratified_sample(df, "W", n_sub)
  df_sub$X_cols_attr <- NULL   # clean up

  saveRDS(list(data   = df_sub,
               X_cols = X_cols,
               W_col  = "W",
               Y_col  = "Y",
               Y_options = c(response = "Response (binary)")),
          dest)
  cat(sprintf("[Lenta] Saved. %d rows, %d features.\n\n", nrow(df_sub), length(X_cols)))
  invisible(TRUE)
}

# ── 3. Criteo Uplift ──────────────────────────────────────────────────────────

prepare_criteo <- function(out_dir) {
  dest <- file.path(out_dir, "criteo_raw.rds")
  if (file.exists(dest)) {
    cat("[Criteo] Already exists, skipping.\n\n"); return(invisible(TRUE))
  }
  # Criteo v2.1 public URL (~2.7 GB gzipped)
  url <- "http://go.criteo.net/criteo-research-uplift-v2.1.csv.gz"
  cat("[Criteo] Downloading (this may take several minutes, file is ~2.7 GB)...\n")
  tmp_gz <- tempfile(fileext = ".csv.gz")
  ok <- safe_download(url, tmp_gz, "Criteo Uplift v2.1")

  if (!ok) {
    cat("[Criteo] Download failed.\n")
    cat("  Manual steps:\n")
    cat("  1. Download 'criteo-research-uplift-v2.1.csv.gz' from:\n")
    cat("     https://ailab.criteo.com/criteo-uplift-prediction-dataset/\n")
    cat(sprintf("  2. Place it at: %s/criteo_raw.csv.gz\n", out_dir))
    cat("  3. Re-run this script.\n\n")
    # Try manual fallback
    manual_gz  <- file.path(out_dir, "criteo_raw.csv.gz")
    manual_csv <- file.path(out_dir, "criteo_raw.csv")
    if (file.exists(manual_gz)) {
      cat("[Criteo] Found manual .gz file, using it.\n")
      tmp_gz <- manual_gz
    } else if (file.exists(manual_csv)) {
      cat("[Criteo] Found manual CSV, loading first 200K rows...\n")
      df <- read.csv(manual_csv, nrows = 200000)
      ok <- TRUE
      tmp_gz <- NULL
    } else {
      return(invisible(FALSE))
    }
  }

  if (!is.null(tmp_gz)) {
    cat("[Criteo] Reading first 1M rows from gzip (to ensure both W=0 and W=1 present)...\n")
    df <- tryCatch(
      read.csv(gzfile(tmp_gz), nrows = 1000000),
      error = function(e) { cat(sprintf("[Criteo] Read error: %s\n", conditionMessage(e))); NULL }
    )
    if (is.null(df)) return(invisible(FALSE))
  }

  # Criteo v2.1 columns: treatment (always 1), exposure (actual randomization), visit, conversion, f0..f11
  # Use 'exposure' as W: 84% treated (ad shown), 16% control (ad not shown)
  X_cols <- paste0("f", 0:11)
  df$W <- as.integer(df$exposure == 1)
  cat(sprintf("[Criteo] W (exposure) table: 0=%d, 1=%d\n",
              sum(df$W==0), sum(df$W==1)))
  df$Y_visit      <- as.integer(df$visit)
  df$Y_conversion <- as.integer(df$conversion)

  # drop rows with NA
  df <- df[complete.cases(df[, c("W", "Y_visit", X_cols)]), ]

  # subsample 100K
  n_sub  <- min(100000L, nrow(df))
  set.seed(42)
  df_sub <- df[sample(nrow(df), n_sub), ]

  saveRDS(list(data      = df_sub,
               X_cols    = X_cols,
               W_col     = "W",
               Y_options = c(visit       = "Visit (binary)",
                             conversion  = "Conversion (binary)")),
          dest)
  cat(sprintf("[Criteo] Saved. %d rows, %d features.\n\n", nrow(df_sub), length(X_cols)))
  invisible(TRUE)
}

# ── Run all ───────────────────────────────────────────────────────────────────

prepare_hillstrom(OUT_DIR)
prepare_lenta(OUT_DIR)
prepare_criteo(OUT_DIR)

cat("=== Done ===\n")
cat("Files in results/real/:\n")
for (f in list.files(OUT_DIR)) cat(sprintf("  %s\n", f))
