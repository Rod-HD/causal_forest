# app_real.R  —  Causal Forest Real-Dataset Showcase
#
# Usage: Rscript -e "shiny::runApp('app_real.R', launch.browser=TRUE)"
#
# Demonstrates Causal Forest on 3 real marketing datasets:
#   Hillstrom MineThatData (email campaign)
#   Lenta RetailHero (SMS campaign)
#   Criteo Uplift (ad exposure)
#
# Dual mode: pre-trained results load instantly; custom run via UI.

suppressPackageStartupMessages({
  library(shiny)
  library(ggplot2)
  library(plotly)
  library(dplyr)
  library(scales)
  library(grf)
})

# Robust script-dir resolution — works under Rscript, shiny::runApp, and source().
resolve_sd <- function() {
  # 1) sys.frame trick (works under Rscript / source)
  s <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(s)) return(normalizePath(dirname(s), mustWork = FALSE))
  # 2) shiny::runApp sets this option when running app.R
  app_dir <- getOption("shiny.application.dir", NULL)
  if (!is.null(app_dir) && dir.exists(app_dir)) return(normalizePath(app_dir))
  # 3) Walk cwd up to find methods.R + dgp.R (signature of r_repro folder)
  cwd <- getwd()
  for (candidate in c(cwd, file.path(cwd, "r_repro"),
                       file.path(cwd, "cf_repro", "r_repro"))) {
    if (file.exists(file.path(candidate, "methods.R")) &&
        file.exists(file.path(candidate, "dgp.R")))
      return(normalizePath(candidate))
  }
  # 4) Last resort: cwd
  cwd
}
SD      <- resolve_sd()
RES_DIR <- file.path(SD, "..", "results", "real")
RAW_DIR <- RES_DIR
message(sprintf("[app_real] SD      = %s", SD))
message(sprintf("[app_real] RES_DIR = %s", normalizePath(RES_DIR, mustWork = FALSE)))
if (!file.exists(file.path(SD, "methods.R")))
  stop(sprintf("methods.R not found in SD=%s. Launch the app from cf_repro/r_repro/.", SD))
source(file.path(SD, "methods.R"))

# ── Dataset registry ──────────────────────────────────────────────────────────

DATASETS <- list(
  hillstrom = list(
    label          = "Hillstrom MineThatData (n≈43K)",
    has_group      = TRUE,
    groups         = c(men   = "Men's Email vs Control",
                       women = "Women's Email vs Control"),
    outcomes       = c(visit      = "Visit (binary)",
                       conversion = "Conversion (binary)",
                       spend      = "Spend (continuous)"),
    X_cols         = c("recency","history","mens","womens",
                       "zip_code_enc","newbie","channel_enc"),
    show_subsample = FALSE,
    max_n          = 45000L,
    desc           = paste(
      "Kevin Hillstrom MineThatData E-Mail Analytics Challenge (2008)",
      "64,000 customers | Binary email campaign (men's / women's clothing)",
      "Outcome: visit site, make a purchase, or total spend",
      "Goal: identify which customers are most responsive to email.",
      sep = "\n")
  ),
  lenta = list(
    label          = "Lenta RetailHero (n≈100K subsample)",
    has_group      = FALSE,
    groups         = NULL,
    outcomes       = c(response = "Response (binary)"),
    X_cols         = NULL,
    show_subsample = TRUE,
    max_n          = 100000L,
    desc           = paste(
      "X5 RetailHero / Lenta Uplift Competition dataset",
      "~687K customers | Binary SMS promotional campaign",
      "Outcome: customer response (purchase after SMS)",
      "Goal: find customers most likely to be persuaded by SMS.",
      sep = "\n")
  ),
  criteo = list(
    label          = "Criteo Uplift v2.1 (n≈100K subsample)",
    has_group      = FALSE,
    groups         = NULL,
    outcomes       = c(visit      = "Visit (binary)",
                       conversion = "Conversion (binary)"),
    X_cols         = paste0("f", 0:11),
    show_subsample = TRUE,
    max_n          = 100000L,
    desc           = paste(
      "Criteo Uplift Modeling Dataset v2.1",
      "14M rows (100K subsample used) | W = ad exposure (0/1)",
      "Features: 12 anonymized numeric covariates (f0–f11)",
      "Goal: estimate per-user ad effect on visit/conversion.",
      sep = "\n")
  ),
  upload = list(
    label          = "Upload your own CSV",
    has_group      = FALSE,
    groups         = NULL,
    outcomes       = NULL,
    X_cols         = NULL,
    show_subsample = TRUE,
    max_n          = 50000L,
    desc           = "Upload a CSV with treatment (W), outcome (Y), and feature columns."
  )
)

SEG_HIGH_DEFAULT <- 0.05
SEG_LOW_DEFAULT  <- -0.05

# ── Helper functions ──────────────────────────────────────────────────────────

rds_key <- function(ds, group, outcome) {
  if (ds == "hillstrom") paste0("hillstrom_", group, "_", outcome)
  else                   paste0(ds, "_", outcome)
}

rds_path <- function(key) file.path(RES_DIR, paste0(key, ".rds"))

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

compute_segments <- function(res, seg_high = SEG_HIGH_DEFAULT, seg_low = SEG_LOW_DEFAULT) {
  tau  <- res$tau_hat
  W    <- res$W_test
  Y    <- res$Y_test
  baseline_treated <- if (sum(W == 1) > 0) mean(Y[W == 1], na.rm = TRUE) else 0.5
  neutral <- tau >= seg_low & tau <= seg_high
  list(
    persuadable = sum(tau >  seg_high),
    dnd         = sum(tau <  seg_low),
    sure_thing  = sum(neutral &  baseline_treated >  0.5),
    lost_cause  = sum(neutral & (baseline_treated <= 0.5)),
    n           = length(tau),
    baseline    = baseline_treated
  )
}

compute_uplift <- function(res) {
  tau <- res$tau_hat
  Y   <- res$Y_test
  n   <- length(tau)
  total_conv <- sum(Y, na.rm = TRUE)
  if (total_conv == 0 || total_conv == n) return(NULL)
  ord       <- order(tau, decreasing = TRUE)
  cum_conv  <- cumsum(Y[ord]) / total_conv
  pct_pop   <- seq_len(n) / n
  qini      <- mean(cum_conv - pct_pop, na.rm = TRUE)
  # thin to 300 points for plotly performance
  idx       <- unique(c(round(seq(1, n, length.out = 300)), n))
  data.frame(pct_targeted = pct_pop[idx],
             cum_gain     = cum_conv[idx],
             random       = pct_pop[idx],
             qini         = qini)
}

detect_columns <- function(df) {
  n_rows <- nrow(df)
  is_binary <- function(x) {
    u <- unique(x[!is.na(x)])
    length(u) == 2 && all(sort(as.numeric(u)) == c(0, 1))
  }
  is_id <- function(x) is.numeric(x) && length(unique(x)) == n_rows
  binary_cols <- names(df)[sapply(df, is_binary)]
  id_cols     <- names(df)[sapply(df, is_id)]
  numeric_cols <- names(df)[sapply(df, is.numeric)]
  W_candidate <- setdiff(binary_cols, id_cols)[1]
  y_pattern   <- "convert|visit|spend|outcome|revenue|response|target|^y$"
  Y_candidates <- setdiff(numeric_cols, c(W_candidate %||% "", id_cols))
  Y_match      <- grep(y_pattern, Y_candidates, ignore.case = TRUE, value = TRUE)
  Y_candidate  <- if (length(Y_match) > 0) Y_match[1] else Y_candidates[1]
  X_candidates <- setdiff(names(df), c(W_candidate %||% "", Y_candidate %||% "", id_cols))
  list(W = W_candidate %||% names(df)[1],
       Y = Y_candidate %||% names(df)[2],
       X = X_candidates,
       numeric_cols = numeric_cols)
}

coerce_X_matrix <- function(df, X_cols) {
  X_mat <- as.matrix(df[, X_cols, drop = FALSE])
  for (j in seq_len(ncol(X_mat))) {
    if (!is.numeric(X_mat[, j]))
      X_mat[, j] <- as.numeric(factor(X_mat[, j]))
  }
  storage.mode(X_mat) <- "double"
  X_mat
}

stat_item <- function(val, lbl) {
  div(class = "stat-item",
      div(class = "stat-val", val),
      div(class = "stat-lbl", lbl))
}

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { background:#f5f6fa; font-family:'Segoe UI',sans-serif; }
    h2   { color:#2c3e50; font-weight:700; margin-bottom:4px; }
    .subtitle { color:#777; font-size:14px; margin-bottom:8px; }
    .card { background:#fff; border-radius:8px; padding:16px 18px;
            box-shadow:0 1px 4px rgba(0,0,0,0.08); margin-bottom:14px; }
    .card h4 { color:#2c3e50; margin:0 0 10px; font-weight:600; font-size:13px;
               text-transform:uppercase; letter-spacing:0.4px; }
    .desc-box { background:#f0f4f8; border-left:4px solid #2166ac;
                border-radius:4px; padding:10px 14px; font-size:12px;
                white-space:pre-line; line-height:1.7; color:#444; margin-top:8px; }
    .stat-row  { display:flex; gap:10px; flex-wrap:wrap; margin-bottom:12px; }
    .stat-item { background:#f0f4f8; border-radius:6px; padding:10px 14px;
                 min-width:90px; text-align:center; flex:1; }
    .stat-val  { font-size:20px; font-weight:700; color:#2166ac; }
    .stat-lbl  { font-size:10px; color:#888; margin-top:2px;
                 text-transform:uppercase; letter-spacing:0.4px; }
    .tab-content { background:#fff; border-radius:0 8px 8px 8px;
                   padding:20px; box-shadow:0 1px 4px rgba(0,0,0,0.08); }
    .nav-tabs>li.active>a { font-weight:600; color:#2166ac !important; }
    .badge-pretrained { background:#27ae60; color:#fff; border-radius:4px;
                        padding:4px 10px; font-size:11px; font-weight:600; }
    .badge-custom { background:#e67e22; color:#fff; border-radius:4px;
                    padding:4px 10px; font-size:11px; font-weight:600; }
    .badge-none   { background:#95a5a6; color:#fff; border-radius:4px;
                    padding:4px 10px; font-size:11px; font-weight:600; }
    .seg-bar { display:flex; gap:6px; margin:10px 0 16px; flex-wrap:wrap; }
    .seg-item { padding:8px 12px; border-radius:6px; font-size:12px; font-weight:600; flex:1; text-align:center; }
    .seg-persuadable { background:#d4edda; color:#155724; }
    .seg-dnd         { background:#f8d7da; color:#721c24; }
    .seg-surething   { background:#d1ecf1; color:#0c5460; }
    .seg-lostcause   { background:#fff3cd; color:#856404; }
    .run-btn { background:#2166ac!important; color:#fff!important;
               font-weight:600!important; border:none!important; width:100%; }
    .no-data-msg { text-align:center; color:#999; padding:60px 20px;
                   font-size:15px; }
  "))),

  div(style = "padding:20px 30px",
    fluidRow(
      column(9,
        h2("Causal Forest — Real Data Showcase"),
        div(class = "subtitle",
            "Heterogeneous treatment effects on real marketing datasets  ·  ",
            "Wager & Athey (2018) method via ",
            code("grf"), " package")
      ),
      column(3, style = "text-align:right; padding-top:18px",
        uiOutput("mode_badge")
      )
    ),

    fluidRow(
      # ── Sidebar ────────────────────────────────────────────────────────────
      column(3,
        div(class = "card",
          h4("Dataset"),
          selectInput("dataset", NULL,
            choices  = setNames(names(DATASETS), sapply(DATASETS, `[[`, "label")),
            selected = "hillstrom", width = "100%"),

          # Hillstrom group selector
          conditionalPanel("input.dataset == 'hillstrom'",
            radioButtons("hillstrom_group", "Treatment group:",
              choices  = c(men = "Men's Email vs Control",
                           women = "Women's Email vs Control"),
              selected = "men")
          ),

          # Outcome selector
          uiOutput("outcome_selector"),

          # Upload CSV
          conditionalPanel("input.dataset == 'upload'",
            fileInput("csv_file",
                      "Upload CSV (≤200 MB)",
                      accept = c(".csv", "text/csv", "text/comma-separated-values")),
            tags$div(style = "font-size:11px; color:#888; margin-top:-8px; margin-bottom:8px",
              "CSV file only. Pre-trained .rds files are loaded automatically from disk — do not upload them here."),
            uiOutput("upload_col_selectors")
          ),

          div(class = "desc-box", textOutput("dataset_desc"))
        ),

        div(class = "card",
          h4("Custom Run (optional)"),
          tags$div(style = "font-size:11px; color:#888; margin-top:-6px; margin-bottom:10px; line-height:1.5",
            "Pre-trained results auto-load when you change dataset/outcome — no button needed. ",
            "Use this card only to re-train with custom settings (slower)."),
          # Subsample slider (hidden for Hillstrom)
          conditionalPanel("input.dataset != 'hillstrom'",
            uiOutput("subsample_slider_ui")
          ),
          sliderInput("num_trees", "Number of trees:",
            min = 200, max = 2000, value = 500, step = 100, width = "100%"),
          # Top-K features toggle (visible after first train, when VI is available)
          uiOutput("topk_toggle_ui"),
          uiOutput("eta_display"),
          br(),
          uiOutput("run_btn_ui")
        )
      ),

      # ── Main panel ─────────────────────────────────────────────────────────
      column(9,
        tabsetPanel(id = "main_tabs", type = "tabs",

          tabPanel("CATE Overview",
            div(class = "tab-content",
              br(),
              uiOutput("tab_cate_overview")
            )
          ),

          tabPanel("Targeting",
            div(class = "tab-content",
              br(),
              uiOutput("tab_targeting")
            )
          ),

          tabPanel("Variable Importance",
            div(class = "tab-content",
              br(),
              uiOutput("tab_varimp")
            )
          ),

          tabPanel("Results Table",
            div(class = "tab-content",
              br(),
              uiOutput("tab_results_table")
            )
          )
        )
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # Allow CSV uploads up to 200 MB (default is 5 MB)
  options(shiny.maxRequestSize = 200 * 1024^2)

  results_rv <- reactiveVal(NULL)

  # ── Dynamic UI ──────────────────────────────────────────────────────────────

  output$outcome_selector <- renderUI({
    ds <- input$dataset
    if (ds == "upload") return(NULL)
    outcomes <- DATASETS[[ds]]$outcomes
    if (is.null(outcomes)) return(NULL)
    # choices: name = display label, value = internal key (e.g. "visit", "conversion")
    choice_vec <- setNames(names(outcomes), unname(outcomes))
    selectInput("outcome", "Outcome:", choices = choice_vec,
                selected = names(outcomes)[1], width = "100%")
  })

  output$dataset_desc <- renderText({
    DATASETS[[input$dataset]]$desc %||% ""
  })

  output$subsample_slider_ui <- renderUI({
    ds   <- input$dataset
    meta <- DATASETS[[ds]]
    if (!meta$show_subsample) return(NULL)
    max_n   <- meta$max_n
    default <- min(10000L, max_n)
    sliderInput("subsample_n", "Subsample n:",
                min = 1000, max = max_n, value = default,
                step = 1000, width = "100%")
  })

  output$eta_display <- renderUI({
    n_trees <- input$num_trees %||% 500
    n_train <- if (isTRUE(input$dataset == "hillstrom")) {
      34000L
    } else {
      floor((input$subsample_n %||% 10000L) * 0.8)
    }
    est_sec <- round((n_train / 10000) * (n_trees / 500) * 35)
    div(style = "font-size:12px; color:#888; margin-top:4px",
        sprintf("Est. ~%ds  (n_train ≈ %s)", est_sec, scales::comma(n_train)))
  })

  # Read uploaded CSV once (sample), cache via reactive
  upload_preview <- reactive({
    req(input$csv_file)
    tryCatch(read.csv(input$csv_file$datapath, nrows = 2000), error = function(e) NULL)
  })

  feature_quick_stats <- function(df) {
    do.call(rbind, lapply(names(df), function(cn) {
      x <- df[[cn]]
      n_unique <- length(unique(x[!is.na(x)]))
      type <- if (is.numeric(x)) {
                if (n_unique == 2)        "binary"
                else if (n_unique <= 20)  "ordinal/cat"
                else                      "numeric"
              } else if (is.character(x) || is.factor(x)) {
                if (n_unique == nrow(df)) "id-like"
                else                      "categorical"
              } else "other"
      data.frame(
        Column   = cn,
        Type     = type,
        Unique   = n_unique,
        `% NA`   = sprintf("%.1f%%", 100 * mean(is.na(x))),
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }))
  }

  output$upload_col_selectors <- renderUI({
    df <- upload_preview()
    req(!is.null(df))
    cols <- detect_columns(df)
    tagList(
      selectInput("upload_W", "Treatment column (W):",
                  choices = names(df), selected = cols$W),
      selectInput("upload_Y", "Outcome column (Y):",
                  choices = cols$numeric_cols, selected = cols$Y),
      checkboxGroupInput("upload_X", "Feature columns (X):",
                         choices  = names(df),
                         selected = cols$X),
      tags$details(
        tags$summary(style = "cursor:pointer; color:#2166ac; font-size:12px; margin-top:8px",
          "Show feature Quick Stats (click)"),
        tags$div(style = "max-height:260px; overflow-y:auto; margin-top:6px",
          tableOutput("upload_quick_stats"))
      )
    )
  })

  output$upload_quick_stats <- renderTable({
    df <- upload_preview()
    req(!is.null(df))
    feature_quick_stats(df)
  }, striped = TRUE, hover = TRUE, bordered = TRUE,
     width = "100%", spacing = "xs")

  # ── Dynamic Run button label ───────────────────────────────────────────────

  output$run_btn_ui <- renderUI({
    res <- results_rv()
    has_pre <- !is.null(res) && isTRUE(res$mode == "pretrained")
    label <- if (has_pre) {
      tagList(icon("rotate"), " Re-train with custom settings")
    } else if (input$dataset == "upload") {
      tagList(icon("play"), " Run Causal Forest on uploaded CSV")
    } else {
      tagList(icon("play"), " Run Causal Forest")
    }
    actionButton("run_btn", label = label,
                 class = "btn btn-primary run-btn")
  })

  # ── Top-K features toggle (Q1.B) ───────────────────────────────────────────

  output$topk_toggle_ui <- renderUI({
    res <- results_rv()
    if (is.null(res) || is.null(res$var_importance) ||
        nrow(res$var_importance) < 5) return(NULL)
    max_k <- nrow(res$var_importance)
    tagList(
      checkboxInput("use_topk", paste0("Retrain with top-K features only (current p=", max_k, ")"),
                    value = FALSE),
      conditionalPanel("input.use_topk == true",
        sliderInput("topk_n", "K:", min = 2, max = max_k,
                    value = min(10, max_k), step = 1, width = "100%")
      )
    )
  })

  # ── Pretrained key ──────────────────────────────────────────────────────────

  pretrained_key <- reactive({
    ds <- input$dataset
    req(ds != "upload")
    if (ds == "hillstrom") {
      req(input$hillstrom_group)
      oc <- input$outcome %||% "visit"
      req(oc %in% names(DATASETS[["hillstrom"]]$outcomes))
      rds_key("hillstrom", input$hillstrom_group, oc)
    } else {
      oc <- input$outcome
      req(!is.null(oc), oc %in% names(DATASETS[[ds]]$outcomes))
      rds_key(ds, NULL, oc)
    }
  })

  # ── Load pretrained automatically ──────────────────────────────────────────

  last_loaded_key <- reactiveVal(NULL)

  observe({
    key <- tryCatch(pretrained_key(), error = function(e) NULL)
    if (is.null(key)) return()
    path <- rds_path(key)
    if (file.exists(path)) {
      t0  <- Sys.time()
      res <- readRDS(path)
      res$mode <- "pretrained"
      load_ms  <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000
      results_rv(res)
      # Flash notification only on key change (avoid spam on re-render)
      if (!isTRUE(last_loaded_key() == key)) {
        showNotification(
          tags$span(
            tags$b("Loaded pre-trained model"),
            tags$br(),
            sprintf("%s  ·  %s observations  ·  ready in %.0f ms",
                    key, scales::comma(res$n_train + res$n_test), load_ms)
          ),
          duration = 2.5, type = "message"
        )
        last_loaded_key(key)
      }
    } else {
      results_rv(NULL)
    }
  })

  # ── Real-time run ──────────────────────────────────────────────────────────

  observeEvent(input$run_btn, {
    ds <- input$dataset

    # ── Step 1: load + prep (fast, ~1s) ──────────────────────────────────────
    notif_id <- showNotification(
      "Step 1/3 — Loading and preparing data...",
      duration = NULL, type = "message", closeButton = FALSE
    )

    df <- tryCatch({
      if (ds == "upload") {
        req(input$csv_file)
        read.csv(input$csv_file$datapath)
      } else {
        raw_path <- file.path(RAW_DIR, paste0(ds, "_raw.rds"))
        if (!file.exists(raw_path)) stop(paste("Raw data not found:", raw_path,
          "\nRun prepare_real_data.R first."))
        raw <- readRDS(raw_path)
        if (ds == "hillstrom") raw[[input$hillstrom_group]] else raw$data
      }
    }, error = function(e) {
      removeNotification(notif_id)
      showNotification(conditionMessage(e), type = "error", duration = 8)
      NULL
    })
    req(!is.null(df))

    # Determine columns
    if (ds == "upload") {
      req(input$upload_W, input$upload_Y, length(input$upload_X) > 0)
      W_col  <- input$upload_W
      Y_col  <- input$upload_Y
      X_cols <- input$upload_X
    } else if (ds == "hillstrom") {
      raw    <- readRDS(file.path(RAW_DIR, "hillstrom_raw.rds"))
      X_cols <- raw$X_cols
      W_col  <- "W"
      Y_col  <- input$outcome %||% "visit"
    } else {
      raw    <- readRDS(file.path(RAW_DIR, paste0(ds, "_raw.rds")))
      X_cols <- raw$X_cols
      W_col  <- "W"
      Y_col  <- if (ds == "criteo") paste0("Y_", input$outcome %||% "visit") else "Y"
    }

    # Top-K feature filter (Q1.B) — uses VI from prior pretrained/custom result
    if (isTRUE(input$use_topk)) {
      prev <- results_rv()
      if (!is.null(prev) && !is.null(prev$var_importance)) {
        vi <- prev$var_importance
        k  <- min(as.integer(input$topk_n %||% 10), nrow(vi))
        top_feats <- vi$feature[order(vi$importance, decreasing = TRUE)][seq_len(k)]
        kept <- intersect(top_feats, X_cols)
        if (length(kept) >= 2) {
          X_cols <- kept
          showNotification(
            sprintf("Top-K mode: using %d features instead of %d.",
                    length(kept), length(raw$X_cols %||% X_cols)),
            type = "message", duration = 4
          )
        }
      }
    }

    # Subsample for non-Hillstrom
    if (ds != "hillstrom" && !is.null(input$subsample_n)) {
      n_sub <- min(as.integer(input$subsample_n), nrow(df))
      set.seed(42)
      df <- df[sample(nrow(df), n_sub), ]
    }

    # Prepare matrices
    X_mat <- coerce_X_matrix(df, X_cols)
    W_vec <- as.numeric(df[[W_col]])
    Y_vec <- as.numeric(df[[Y_col]])
    ok    <- complete.cases(X_mat) & !is.na(W_vec) & !is.na(Y_vec)
    X_mat <- X_mat[ok, ]; W_vec <- W_vec[ok]; Y_vec <- Y_vec[ok]

    set.seed(42)
    n      <- nrow(X_mat)
    tr_idx <- sample(n, floor(n * 0.8))
    te_idx <- setdiff(seq_len(n), tr_idx)
    X_train <- X_mat[tr_idx, ]; W_train <- W_vec[tr_idx]; Y_train <- Y_vec[tr_idx]
    X_test  <- X_mat[te_idx, ]; W_test  <- W_vec[te_idx]; Y_test  <- Y_vec[te_idx]

    # ── Step 2: train CF (slow, blocks UI — this is expected) ─────────────────
    removeNotification(notif_id)
    n_trees <- input$num_trees
    est_sec <- round((nrow(X_train) / 10000) * (n_trees / 500) * 35)
    notif_id2 <- showNotification(
      tags$span(
        tags$b("Step 2/3 — Growing causal forest"),
        tags$br(),
        sprintf("n_train = %s  ·  trees = %d  ·  est. ~%ds",
                scales::comma(nrow(X_train)), n_trees, est_sec),
        tags$br(),
        tags$span(style = "color:#aaa; font-size:11px",
          "UI is paused while R trains the forest. Results will appear when done.")
      ),
      duration = NULL, type = "message", closeButton = FALSE
    )

    cf <- grow_causal_forest(X_train, W_train, Y_train,
                             num_trees       = n_trees,
                             sample_fraction = 0.5,
                             seed            = 42)

    # ── Step 3: predict + save (fast, ~2s) ────────────────────────────────────
    removeNotification(notif_id2)
    showNotification("Step 3/3 — Computing predictions...",
                     duration = NULL, type = "message", id = "notif_pred",
                     closeButton = FALSE)

    preds   <- predict(cf, newdata = X_test, estimate.variance = TRUE)
    tau_hat <- as.numeric(preds$predictions)
    se_hat  <- sqrt(pmax(as.numeric(preds$variance.estimates), 0))
    if (all(Y_vec %in% c(0, 1))) tau_hat <- pmax(-1, pmin(1, tau_hat))

    vi_df <- data.frame(
      feature    = X_cols,
      importance = as.numeric(variable_importance(cf)),
      stringsAsFactors = FALSE
    )

    removeNotification("notif_pred")
    showNotification(
      sprintf("Done! n_test = %s  ·  mean CATE = %.4f",
              scales::comma(length(tau_hat)), mean(tau_hat)),
      duration = 5, type = "message"
    )

    results_rv(list(
      tau_hat       = tau_hat,
      tau_lower     = tau_hat - 1.96 * se_hat,
      tau_upper     = tau_hat + 1.96 * se_hat,
      X_test        = X_test,
      W_test        = W_test,
      Y_test        = Y_test,
      X_cols        = X_cols,
      var_importance = vi_df,
      n_train       = nrow(X_train),
      n_test        = nrow(X_test),
      outcome       = Y_col,
      dataset_label = ds,
      trained_at    = Sys.time(),
      mode          = "custom"
    ))
  })

  # ── Mode badge ──────────────────────────────────────────────────────────────

  output$mode_badge <- renderUI({
    res <- results_rv()
    if (is.null(res)) {
      key <- tryCatch(pretrained_key(), error = function(e) NULL)
      hint <- if (is.null(key)) "Select a dataset/outcome"
              else paste0("File missing: ", key, ".rds")
      return(tagList(
        span(class = "badge-none", "No model loaded"),
        div(style = "font-size:11px; color:#999; margin-top:4px", hint)
      ))
    }
    n_total <- scales::comma(res$n_train + res$n_test)
    ts      <- format(res$trained_at, "%Y-%m-%d %H:%M")
    if (res$mode == "pretrained") {
      tagList(
        span(class = "badge-pretrained",
             HTML(paste0("&#x1F512; Pre-trained  &middot;  ", n_total, " obs"))),
        div(style = "font-size:11px; color:#27ae60; margin-top:4px; font-weight:600",
            "Loaded from disk (.rds)"),
        div(style = "font-size:10px; color:#888",
            paste0("Trained: ", ts))
      )
    } else {
      n_trees_used <- isolate(input$num_trees) %||% "?"
      tagList(
        span(class = "badge-custom",
             HTML(paste0("&#x26A1; Custom run  &middot;  ", n_total, " obs"))),
        div(style = "font-size:11px; color:#e67e22; margin-top:4px; font-weight:600",
            paste0("Re-trained just now (trees=", n_trees_used, ")")),
        div(style = "font-size:10px; color:#888",
            paste0("Trained: ", ts)),
        div(style = "margin-top:6px",
          actionLink("reset_to_pretrained",
                     label = tagList(icon("rotate-left"), " Reset to pre-trained"),
                     style = "font-size:11px; color:#2166ac"))
      )
    }
  })

  observeEvent(input$reset_to_pretrained, {
    key <- tryCatch(pretrained_key(), error = function(e) NULL)
    if (is.null(key)) return()
    path <- rds_path(key)
    if (file.exists(path)) {
      res      <- readRDS(path)
      res$mode <- "pretrained"
      results_rv(res)
      last_loaded_key(key)
      showNotification("Restored pre-trained model.", type = "message", duration = 3)
    }
  })

  # ── Segment threshold (outcome-aware) ───────────────────────────────────────

  seg_threshold <- reactive({
    oc <- input$outcome %||% ""
    if (oc == "spend") list(high = 1.0,  low = -1.0)
    else               list(high = 0.05, low = -0.05)
  })

  # ── TAB 1: CATE Overview ────────────────────────────────────────────────────

  output$tab_cate_overview <- renderUI({
    res <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg",
      "No data loaded. Select a dataset or run a custom model."))

    tau <- res$tau_hat
    oc  <- res$outcome %||% ""
    unit_note <- if (oc == "spend") "Values in dollar units." else
                 "Values in probability units (+0.05 = +5 percentage points)."

    tagList(
      div(class = "stat-row",
        stat_item(formatC(mean(tau), digits=4, format="f"),     "Mean CATE"),
        stat_item(formatC(sd(tau),   digits=4, format="f"),     "SD"),
        stat_item(paste0(round(100*mean(tau > 0), 1), "%"),     "% Positive"),
        stat_item(paste0(round(100*mean(tau < 0), 1), "%"),     "% Negative"),
        stat_item(scales::comma(res$n_test),                    "Test obs")
      ),
      plotlyOutput("plot_cate_density", height = "330px"),
      div(class = "desc-box",
          paste0("Dataset: ", res$dataset_label, "  ·  Outcome: ", res$outcome,
                 "  ·  Trained: ", format(res$trained_at, "%Y-%m-%d %H:%M"),
                 "\n", unit_note))
    )
  })

  output$plot_cate_density <- renderPlotly({
    res <- results_rv(); req(!is.null(res))
    tau  <- res$tau_hat
    thr  <- seg_threshold()
    df   <- data.frame(tau = tau)
    p <- ggplot(df, aes(x = tau)) +
      geom_density(fill = "#2166ac", alpha = 0.55, color = "white", linewidth = 0.4) +
      geom_vline(xintercept = 0,        linetype = "dashed", color = "#888888", linewidth = 0.7) +
      geom_vline(xintercept = mean(tau), linetype = "dashed", color = "#e74c3c", linewidth = 0.9) +
      geom_vline(xintercept = c(thr$low, thr$high),
                 linetype = "dotted", color = "#f39c12", linewidth = 0.7) +
      labs(x = "Estimated CATE  (tau-hat)",
           y = "Density",
           title = "Distribution of Individual Treatment Effect Estimates",
           caption = "Red dashed = mean  ·  Orange dotted = segment boundaries") +
      theme_bw(base_size = 12) +
      theme(panel.grid.minor = element_blank(),
            plot.title = element_text(face = "bold", size = 12))
    ggplotly(p) %>% layout(margin = list(t = 50, b = 50))
  })

  # ── TAB 2: Targeting ────────────────────────────────────────────────────────

  segs_rv <- reactive({
    res <- results_rv(); req(!is.null(res))
    thr <- seg_threshold()
    compute_segments(res, thr$high, thr$low)
  })

  uplift_rv <- reactive({
    res <- results_rv(); req(!is.null(res))
    compute_uplift(res)
  })

  output$tab_targeting <- renderUI({
    res  <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg", "No data loaded."))
    segs <- segs_rv()
    pct  <- function(x) paste0(round(100 * x / segs$n, 1), "%")

    tagList(
      div(class = "seg-bar",
        div(class = "seg-item seg-persuadable",
            tags$div(tags$strong("Persuadables")),
            tags$div(paste0(scales::comma(segs$persuadable), "  (", pct(segs$persuadable), ")"))),
        div(class = "seg-item seg-dnd",
            tags$div(tags$strong("Do Not Disturb")),
            tags$div(paste0(scales::comma(segs$dnd), "  (", pct(segs$dnd), ")"))),
        div(class = "seg-item seg-surething",
            tags$div(tags$strong("Sure Things")),
            tags$div(paste0(scales::comma(segs$sure_thing), "  (", pct(segs$sure_thing), ")"))),
        div(class = "seg-item seg-lostcause",
            tags$div(tags$strong("Lost Causes")),
            tags$div(paste0(scales::comma(segs$lost_cause), "  (", pct(segs$lost_cause), ")")))
      ),
      fluidRow(
        column(7, plotlyOutput("plot_uplift", height = "340px")),
        column(5, plotlyOutput("plot_segments_bar", height = "340px"))
      ),
      br(),
      div(class = "card",
        h4("Targeting Recommendations"),
        tableOutput("recommendation_table")
      )
    )
  })

  output$plot_uplift <- renderPlotly({
    udf <- uplift_rv()
    if (is.null(udf)) {
      return(plotly_empty() %>% layout(title="Uplift curve not available (outcome has no variation)"))
    }
    p <- ggplot(udf) +
      geom_line(aes(x = pct_targeted, y = cum_gain,  color = "Model"),  linewidth = 1.1) +
      geom_line(aes(x = pct_targeted, y = random,    color = "Random"), linewidth = 0.8, linetype = "dashed") +
      scale_color_manual(values = c(Model = "#2166ac", Random = "#999999"), name = NULL) +
      scale_x_continuous(labels = scales::percent) +
      scale_y_continuous(labels = scales::percent) +
      labs(x = "% Population Targeted",
           y = "% Conversions Captured",
           title = sprintf("Uplift Curve  |  Qini = %.3f", udf$qini[1])) +
      theme_bw(base_size = 12) +
      theme(legend.position  = "bottom",
            panel.grid.minor = element_blank(),
            plot.title = element_text(face = "bold", size = 12))
    ggplotly(p, tooltip = c("x", "y")) %>%
      layout(legend = list(orientation = "h", y = -0.25), margin = list(t = 50))
  })

  output$plot_segments_bar <- renderPlotly({
    segs <- segs_rv()
    df <- data.frame(
      Segment = c("Persuadables","Do Not Disturb","Sure Things","Lost Causes"),
      Count   = c(segs$persuadable, segs$dnd, segs$sure_thing, segs$lost_cause),
      Color   = c("#27ae60","#e74c3c","#1abc9c","#f39c12"),
      stringsAsFactors = FALSE
    )
    df$Segment <- factor(df$Segment, levels = rev(df$Segment))
    p <- ggplot(df, aes(x = Count, y = Segment, fill = Segment,
                        text = paste0(Segment, ": ", scales::comma(Count)))) +
      geom_col(show.legend = FALSE) +
      scale_fill_manual(values = setNames(df$Color, df$Segment)) +
      scale_x_continuous(labels = scales::comma) +
      labs(x = "Number of customers", y = NULL,
           title = "Customer Segments") +
      theme_bw(base_size = 12) +
      theme(panel.grid.minor = element_blank(),
            plot.title = element_text(face = "bold", size = 12))
    ggplotly(p, tooltip = "text") %>% layout(margin = list(t = 50, l = 10))
  })

  output$recommendation_table <- renderTable({
    res  <- results_rv(); req(!is.null(res))
    segs <- segs_rv()
    thr  <- seg_threshold()
    tau  <- res$tau_hat
    W    <- res$W_test
    Y    <- res$Y_test
    neutral <- tau >= thr$low & tau <= thr$high
    baseline_treated <- if (sum(W == 1) > 0) mean(Y[W == 1], na.rm = TRUE) else 0.5
    data.frame(
      Segment    = c("Persuadables", "Do Not Disturb", "Sure Things", "Lost Causes"),
      Action     = c("TARGET — high ROI, outreach drives uplift",
                     "EXCLUDE — treatment may reduce conversion",
                     "OPTIONAL — already convert, marginal uplift low",
                     "DEPRIORITIZE — low response, no uplift"),
      `Avg CATE` = c(
        if (segs$persuadable > 0) round(mean(tau[tau >  thr$high]), 4) else NA,
        if (segs$dnd         > 0) round(mean(tau[tau <  thr$low]),  4) else NA,
        if (segs$sure_thing  > 0) round(mean(tau[neutral & baseline_treated >  0.5]), 4) else NA,
        if (segs$lost_cause  > 0) round(mean(tau[neutral & baseline_treated <= 0.5]), 4) else NA
      ),
      Size = c(segs$persuadable, segs$dnd, segs$sure_thing, segs$lost_cause),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }, striped = TRUE, hover = TRUE, bordered = TRUE, width = "100%", na = "—")

  # ── TAB 3: Variable Importance ──────────────────────────────────────────────

  output$tab_varimp <- renderUI({
    res <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg", "No data loaded."))
    vi <- res$var_importance
    req(!is.null(vi), nrow(vi) > 0)

    vi_sorted <- vi[order(vi$importance, decreasing = TRUE), ]
    total     <- sum(vi_sorted$importance)
    cum_share <- cumsum(vi_sorted$importance) / total
    k_top3    <- min(3, nrow(vi_sorted))
    share_top3 <- cum_share[k_top3]
    k_for_80  <- which(cum_share >= 0.80)[1]
    if (is.na(k_for_80)) k_for_80 <- nrow(vi_sorted)
    top_names <- paste(vi_sorted$feature[seq_len(k_top3)], collapse = ", ")

    tagList(
      div(class = "desc-box",
        HTML(sprintf(paste0(
          "<b>Top %d features (%s) explain %.0f%% of treatment-effect heterogeneity.</b><br>",
          "It takes <b>%d feature(s)</b> to reach 80%% cumulative importance ",
          "(out of %d total).<br>",
          "<span style='color:#666'>These are your strongest <i>targeting drivers</i> — ",
          "knowing these per customer is enough to predict who responds to treatment. ",
          "Use the &ldquo;top-K&rdquo; checkbox in Custom Run to retrain with only top features.</span>"),
          k_top3, top_names, 100 * share_top3, k_for_80, nrow(vi_sorted)))
      ),
      plotlyOutput("plot_varimp", height = "420px")
    )
  })

  output$plot_varimp <- renderPlotly({
    res <- results_rv(); req(!is.null(res))
    vi  <- res$var_importance
    if (is.null(vi) || nrow(vi) == 0) return(plotly_empty())
    vi  <- vi[order(vi$importance), ]
    vi$feature <- factor(vi$feature, levels = vi$feature)
    p <- ggplot(vi, aes(x = importance, y = feature,
                        text = paste0(feature, ": ", round(importance, 4)))) +
      geom_col(fill = "#2166ac", alpha = 0.8) +
      scale_x_continuous(labels = scales::comma) +
      labs(x = "Variable Importance", y = NULL,
           title = "Causal Forest Variable Importance",
           subtitle = "Higher = more influential in determining treatment effect heterogeneity") +
      theme_bw(base_size = 12) +
      theme(panel.grid.minor = element_blank(),
            plot.title    = element_text(face = "bold", size = 12),
            plot.subtitle = element_text(color = "#666", size = 11))
    ggplotly(p, tooltip = "text") %>%
      layout(margin = list(l = 130, t = 60))
  })

  # ── TAB 4: Results Table ────────────────────────────────────────────────────

  output$tab_results_table <- renderUI({
    res <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg", "No data loaded."))
    tagList(
      fluidRow(
        column(5,
          sliderInput("top_n", "Show top N rows (by |tau|):",
                      min = 10, max = min(500, res$n_test),
                      value = min(100, res$n_test), step = 10, width = "100%")
        ),
        column(7, style = "padding-top:24px; font-size:13px; color:#555",
          paste0("Sorted by |τ̂| descending  ·  ",
                 scales::comma(res$n_test), " total test observations")
        )
      ),
      tableOutput("results_df_table")
    )
  })

  output$results_df_table <- renderTable({
    res <- results_rv(); req(!is.null(res))
    top_n <- min(input$top_n %||% 100L, res$n_test)
    df <- as.data.frame(res$X_test)
    if (!is.null(res$X_cols) && length(res$X_cols) == ncol(df))
      colnames(df) <- res$X_cols
    df$W         <- res$W_test
    df$Y_actual  <- res$Y_test
    df$tau_hat   <- round(res$tau_hat,   4)
    df$CI_lower  <- round(res$tau_lower, 4)
    df$CI_upper  <- round(res$tau_upper, 4)
    df <- df[order(abs(df$tau_hat), decreasing = TRUE), ]
    head(df, top_n)
  }, striped = TRUE, hover = TRUE, bordered = TRUE, width = "100%")

}

shinyApp(ui, server)
