# app_demo.R  -  Live Demo Uplift App for CS114
#
# Usage:  Rscript -e "shiny::runApp('app_demo.R', launch.browser=TRUE)"
#
# Compares 6 uplift learners on 3 marketing datasets + uploaded CSV.
# Highlight: per-customer TREAT / DO NOT TREAT decision with adjustable threshold.
#
# Critical path for 5-minute classroom demo:
#   - Pre-trained Hillstrom x visit loads instantly via results/demo_pretrained/
#   - Tab 1 (overview) -> Tab 2 (comparison) -> Tab 3 (curves) -> Tab 4 (decision)
#   - Tab 5 (upload) is backup feature

suppressPackageStartupMessages({
  library(shiny)
  library(ggplot2)
  library(plotly)
  library(dplyr)
  library(scales)
  library(grf)
  library(ranger)
  library(DT)
})

# ── Script-dir resolution (robust to Rscript / runApp / source) ──────────────
resolve_sd <- function() {
  s <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(s)) return(normalizePath(dirname(s), mustWork = FALSE))
  app_dir <- getOption("shiny.application.dir", NULL)
  if (!is.null(app_dir) && dir.exists(app_dir)) return(normalizePath(app_dir))
  cwd <- getwd()
  for (cand in c(cwd, file.path(cwd, "r_repro"),
                  file.path(cwd, "cf_repro", "r_repro"))) {
    if (file.exists(file.path(cand, "learners.R")) &&
        file.exists(file.path(cand, "metrics.R")))
      return(normalizePath(cand))
  }
  cwd
}
SD <- resolve_sd()
RAW_DIR        <- file.path(SD, "..", "results", "real")
PRETRAIN_DIR   <- file.path(SD, "..", "results", "demo_pretrained")
EXPORT_DIR     <- file.path(SD, "..", "results", "demo_exports")
dir.create(PRETRAIN_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(EXPORT_DIR,   recursive = TRUE, showWarnings = FALSE)

source(file.path(SD, "metrics.R"))
source(file.path(SD, "learners.R"))

# ── Dataset registry ─────────────────────────────────────────────────────────

DATASETS <- list(
  hillstrom = list(
    label    = "Hillstrom MineThatData",
    has_group = TRUE,
    groups   = c(men = "Men's Email vs Control",
                 women = "Women's Email vs Control"),
    outcomes = c(visit      = "Visit (binary)",
                 conversion = "Conversion (binary)",
                 spend      = "Spend (continuous)"),
    max_n    = 45000L,
    desc     = "MineThatData Email Analytics Challenge (Hillstrom 2008). 64K customers, randomised email campaign (Men's / Women's / Control). Features fully interpretable."
  ),
  lenta = list(
    label    = "Lenta RetailHero",
    has_group = FALSE,
    outcomes = c(response = "Response (binary)"),
    max_n    = 100000L,
    desc     = "Lenta X5 RetailHero Uplift Competition (~687K customers, SMS campaign). Subsampled to 100K for demo speed."
  ),
  criteo = list(
    label    = "Criteo Uplift v2.1",
    has_group = FALSE,
    outcomes = c(visit = "Visit (binary)", conversion = "Conversion (binary)"),
    max_n    = 100000L,
    desc     = "Criteo Uplift Modeling v2.1 (14M rows, 12 anonymised features). Subsampled to 100K for demo speed."
  ),
  upload = list(
    label    = "Upload your own CSV",
    has_group = FALSE,
    outcomes = NULL,
    max_n    = 50000L,
    desc     = "Upload a CSV with treatment (W), outcome (Y), and feature columns. Auto-detected."
  )
)

# Default demo target — pre-trained file goes here
DEFAULT_DS      <- "hillstrom"
DEFAULT_GROUP   <- "men"
DEFAULT_OUTCOME <- "visit"
DEFAULT_NTREES  <- 500L

LEARNER_ORDER <- c("standard_clf", "s_learner", "t_learner",
                   "x_learner", "causal_tree", "causal_forest")
LEARNER_LABELS <- c(
  standard_clf  = "Standard Classifier",
  s_learner     = "S-Learner",
  t_learner     = "T-Learner",
  x_learner     = "X-Learner",
  causal_tree   = "Causal Tree (50)",
  causal_forest = "Causal Forest"
)
LEARNER_COLORS <- c(
  "Standard Classifier" = "#7f8c8d",
  "S-Learner"           = "#f1c40f",
  "T-Learner"           = "#e67e22",
  "X-Learner"           = "#9b59b6",
  "Causal Tree (50)"    = "#5aa1d3",
  "Causal Forest"       = "#2166ac"
)

# ── Helpers ──────────────────────────────────────────────────────────────────

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

# Unified plotly styling — avoids legend overlap, ensures title visibility
#   title       : string to show as plot title (rendered via layout, not ggplot)
#   legend_pos  : "bottom" / "right" / "none"
#   margin_l/r/t/b : pixel margins
style_plotly <- function(p, title = NULL, legend_pos = "bottom",
                          margin_l = 60, margin_r = 30,
                          margin_t = 60, margin_b = 80) {
  args <- list(
    title = if (!is.null(title)) list(
      text = title, x = 0.5, xanchor = "center",
      font = list(size = 13, color = "#2c3e50")
    ) else NULL,
    margin = list(l = margin_l, r = margin_r, t = margin_t, b = margin_b,
                  pad = 4),
    hoverlabel = list(font = list(size = 12)),
    font = list(family = "Segoe UI, sans-serif")
  )
  if (legend_pos == "bottom") {
    args$legend <- list(orientation = "h",
                        x = 0.5, xanchor = "center",
                        y = -0.18, yanchor = "top",
                        bgcolor = "rgba(255,255,255,0.7)",
                        bordercolor = "rgba(0,0,0,0.1)", borderwidth = 1,
                        font = list(size = 11))
  } else if (legend_pos == "right") {
    args$legend <- list(orientation = "v",
                        x = 1.02, xanchor = "left",
                        y = 1.0, yanchor = "top",
                        bgcolor = "rgba(255,255,255,0.7)",
                        font = list(size = 11))
  } else if (legend_pos == "none") {
    args$showlegend <- FALSE
  }
  do.call(plotly::layout, c(list(p = p), args))
}

coerce_X_matrix <- function(df, X_cols) {
  X <- as.matrix(df[, X_cols, drop = FALSE])
  for (j in seq_len(ncol(X))) {
    if (!is.numeric(X[, j])) X[, j] <- as.numeric(factor(X[, j]))
  }
  storage.mode(X) <- "double"
  X
}

detect_columns <- function(df) {
  n <- nrow(df)
  is_binary <- function(x) {
    u <- unique(x[!is.na(x)])
    length(u) == 2 && all(sort(as.numeric(u)) == c(0, 1))
  }
  binary_cols  <- names(df)[sapply(df, is_binary)]
  numeric_cols <- names(df)[sapply(df, is.numeric)]
  W_cand <- binary_cols[1]
  y_pat  <- "convert|visit|spend|outcome|revenue|response|target|^y$"
  Y_cands <- setdiff(numeric_cols, W_cand %||% "")
  Y_match <- grep(y_pat, Y_cands, ignore.case = TRUE, value = TRUE)
  Y_cand  <- if (length(Y_match) > 0) Y_match[1] else Y_cands[1]
  X_cands <- setdiff(names(df), c(W_cand %||% "", Y_cand %||% ""))
  list(W = W_cand %||% names(df)[1],
       Y = Y_cand %||% names(df)[2],
       X = X_cands, numeric_cols = numeric_cols)
}

# Build train/test split + matrices for a dataset
prepare_xyw <- function(df, X_cols, W_col, Y_col, seed = 42L, max_n = NULL) {
  if (!is.null(max_n) && nrow(df) > max_n) {
    set.seed(seed)
    df <- df[sample(nrow(df), max_n), ]
  }
  X <- coerce_X_matrix(df, X_cols)
  W <- as.numeric(df[[W_col]])
  Y <- as.numeric(df[[Y_col]])
  ok <- complete.cases(X) & !is.na(W) & !is.na(Y)
  X <- X[ok, , drop = FALSE]; W <- W[ok]; Y <- Y[ok]
  n <- nrow(X)
  set.seed(seed)
  tr_idx <- sample(n, floor(n * 0.8))
  te_idx <- setdiff(seq_len(n), tr_idx)
  list(
    X_train = X[tr_idx, , drop = FALSE], W_train = W[tr_idx], Y_train = Y[tr_idx],
    X_test  = X[te_idx, , drop = FALSE], W_test  = W[te_idx], Y_test  = Y[te_idx],
    X_cols  = X_cols
  )
}

# Load dataset by registry key
load_dataset <- function(ds_key, group = NULL, outcome = NULL,
                          upload_df = NULL, upload_cols = NULL) {
  if (ds_key == "upload") {
    if (is.null(upload_df) || is.null(upload_cols)) return(NULL)
    df <- upload_df
    list(df = df,
         X_cols = upload_cols$X, W_col = upload_cols$W, Y_col = upload_cols$Y,
         label = "Uploaded CSV", outcome_label = upload_cols$Y)
  } else {
    raw_path <- file.path(RAW_DIR, paste0(ds_key, "_raw.rds"))
    if (!file.exists(raw_path)) {
      stop(sprintf("Raw data not found: %s\nRun prepare_real_data.R first.", raw_path))
    }
    raw <- readRDS(raw_path)
    if (ds_key == "hillstrom") {
      df <- raw[[group %||% "men"]]
      X_cols <- raw$X_cols
      Y_col  <- outcome %||% "visit"
    } else if (ds_key == "criteo") {
      df <- raw$data
      X_cols <- raw$X_cols
      Y_col  <- paste0("Y_", outcome %||% "visit")
    } else {
      df <- raw$data
      X_cols <- raw$X_cols
      Y_col  <- "Y"
    }
    list(df = df, X_cols = X_cols, W_col = "W", Y_col = Y_col,
         label = DATASETS[[ds_key]]$label,
         outcome_label = DATASETS[[ds_key]]$outcomes[[outcome %||% "visit"]] %||% Y_col)
  }
}

# Run full training pipeline for a dataset (or pre-trained list)
build_results <- function(ds_key, group, outcome, num_trees,
                           upload_df = NULL, upload_cols = NULL,
                           progress_fn = NULL) {
  meta <- DATASETS[[ds_key]]
  loaded <- load_dataset(ds_key, group, outcome, upload_df, upload_cols)
  split  <- prepare_xyw(loaded$df, loaded$X_cols, loaded$W_col, loaded$Y_col,
                        seed = 42L, max_n = meta$max_n)

  learners <- train_all_learners(
    X_train = split$X_train, W_train = split$W_train, Y_train = split$Y_train,
    X_test  = split$X_test,
    num_trees = num_trees, seed = 42L,
    progress_fn = progress_fn
  )

  # Compute metrics per learner
  metrics_df <- do.call(rbind, lapply(names(learners), function(nm) {
    lr <- learners[[nm]]
    if (!isTRUE(lr$ok)) {
      return(data.frame(method = LEARNER_LABELS[[nm]], auuc = NA,
                        qini = NA, auc = NA, ok = FALSE,
                        train_time = lr$train_time, stringsAsFactors = FALSE))
    }
    tau <- lr$pred$tau_hat
    auc_val <- if (nm == "standard_clf" && !is.null(lr$pred$prob)) {
      auc_score(lr$pred$prob, split$Y_test)
    } else NA_real_
    auuc_val <- if (nm == "standard_clf") NA_real_
                else auuc(tau, split$W_test, split$Y_test)
    qini_val <- if (nm == "standard_clf") NA_real_
                else qini(tau, split$W_test, split$Y_test)
    data.frame(method = LEARNER_LABELS[[nm]],
               auuc = auuc_val, qini = qini_val, auc = auc_val, ok = TRUE,
               train_time = lr$train_time, stringsAsFactors = FALSE)
  }))

  # Variable importance (from CF)
  cf_fit <- learners$causal_forest$fit
  vi_df <- if (!is.null(cf_fit)) compute_var_importance(cf_fit, split$X_cols) else NULL

  list(
    dataset_key   = ds_key,
    dataset_label = loaded$label,
    outcome       = loaded$Y_col,
    outcome_label = loaded$outcome_label %||% loaded$Y_col,
    group         = group,
    n_train       = nrow(split$X_train),
    n_test        = nrow(split$X_test),
    X_cols        = split$X_cols,
    X_train       = split$X_train, W_train = split$W_train, Y_train = split$Y_train,
    X_test        = split$X_test,  W_test  = split$W_test,  Y_test  = split$Y_test,
    learners      = learners,
    metrics       = metrics_df,
    var_importance = vi_df,
    is_binary_Y   = .is_binary_outcome(split$Y_test),
    trained_at    = Sys.time(),
    mode          = "fresh",
    num_trees     = num_trees
  )
}

pretrain_key <- function(ds, group, outcome) {
  if (ds == "hillstrom") paste0("hillstrom_", group, "_", outcome)
  else                   paste0(ds, "_", outcome)
}

# ── UI ───────────────────────────────────────────────────────────────────────

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { background:#f5f6fa; font-family:'Segoe UI',sans-serif; }
    h2   { color:#2c3e50; font-weight:700; margin:0 0 4px; }
    .subtitle { color:#777; font-size:13px; margin-bottom:8px; }
    .card { background:#fff; border-radius:8px; padding:14px 16px;
            box-shadow:0 1px 4px rgba(0,0,0,0.08); margin-bottom:14px; }
    .card h4 { color:#2c3e50; margin:0 0 10px; font-weight:600; font-size:13px;
               text-transform:uppercase; letter-spacing:0.4px; }
    .desc-box { background:#f0f4f8; border-left:4px solid #2166ac;
                border-radius:4px; padding:10px 14px; font-size:12px;
                line-height:1.6; color:#444; margin-top:8px; }
    .stat-row { display:flex; gap:10px; flex-wrap:wrap; margin-bottom:12px; }
    .stat-item { background:#f0f4f8; border-radius:6px; padding:10px 14px;
                 min-width:100px; text-align:center; flex:1; }
    .stat-val { font-size:22px; font-weight:700; color:#2166ac; }
    .stat-lbl { font-size:10px; color:#888; margin-top:2px;
                text-transform:uppercase; letter-spacing:0.4px; }
    .tab-content { background:#fff; border-radius:0 8px 8px 8px;
                   padding:20px; box-shadow:0 1px 4px rgba(0,0,0,0.08); }
    .nav-tabs>li.active>a { font-weight:600; color:#2166ac !important; }
    .badge-pre { background:#27ae60; color:#fff; border-radius:4px;
                 padding:4px 10px; font-size:11px; font-weight:600; }
    .badge-fresh { background:#e67e22; color:#fff; border-radius:4px;
                   padding:4px 10px; font-size:11px; font-weight:600; }
    .badge-none { background:#95a5a6; color:#fff; border-radius:4px;
                  padding:4px 10px; font-size:11px; font-weight:600; }
    .run-btn { background:#2166ac!important; color:#fff!important;
               font-weight:600!important; border:none!important; width:100%; }
    .export-btn { background:#27ae60!important; color:#fff!important;
                  font-weight:600!important; border:none!important; width:100%;
                  margin-top:6px; }
    .no-data-msg { text-align:center; color:#999; padding:60px 20px;
                   font-size:15px; }
    /* Tab 4 customer decision panel */
    .tau-big { font-size:48px; font-weight:800; text-align:center;
               padding:12px 0; line-height:1.0; }
    .tau-ci  { text-align:center; color:#666; font-size:13px; margin-bottom:10px; }
    .decision-treat { background:#27ae60; color:#fff; font-size:28px;
                      font-weight:800; text-align:center; padding:18px;
                      border-radius:8px; margin:14px 0; letter-spacing:1.2px; }
    .decision-no    { background:#e74c3c; color:#fff; font-size:28px;
                      font-weight:800; text-align:center; padding:18px;
                      border-radius:8px; margin:14px 0; letter-spacing:1.2px; }
    .pos-tau { color:#27ae60; } .neg-tau { color:#e74c3c; }
    .learner-status { font-size:11px; padding:2px 8px; border-radius:3px;
                      margin-right:4px; }
    .ls-ok    { background:#d4edda; color:#155724; }
    .ls-fail  { background:#f8d7da; color:#721c24; }
    .ls-pend  { background:#e2e3e5; color:#6c757d; }
    table.dataTable tbody tr.selected td { background:#dbe9f6 !important; }
  "))),

  div(style = "padding:18px 28px",
    fluidRow(
      column(9,
        h2("Causal Forest — Live Demo (CS114)"),
        div(class="subtitle",
          "Compare 6 uplift learners · Per-customer TREAT decision · Hillstrom / Lenta / Criteo / Upload")
      ),
      column(3, style="text-align:right; padding-top:16px",
        uiOutput("mode_badge")
      )
    ),

    fluidRow(
      # ── Sidebar (3/12) ──────────────────────────────────────────────────
      column(3,
        div(class="card",
          h4("Dataset"),
          selectInput("dataset", NULL,
            choices  = setNames(names(DATASETS), sapply(DATASETS, `[[`, "label")),
            selected = DEFAULT_DS, width="100%"),

          conditionalPanel("input.dataset == 'hillstrom'",
            radioButtons("hillstrom_group", "Treatment group:",
              choices = c("Men's Email vs Control" = "men",
                          "Women's Email vs Control" = "women"),
              selected = DEFAULT_GROUP)
          ),

          uiOutput("outcome_selector"),

          conditionalPanel("input.dataset == 'upload'",
            fileInput("csv_file", "Upload CSV (≤200 MB)",
                      accept = c(".csv", "text/csv")),
            uiOutput("upload_col_selectors")
          ),

          div(class="desc-box", textOutput("dataset_desc"))
        ),

        div(class="card",
          h4("Training"),
          sliderInput("num_trees", "Trees per learner:",
            min = 200, max = 1500, value = DEFAULT_NTREES, step = 100, width="100%"),
          uiOutput("eta_display"),
          uiOutput("train_btn_ui"),
          br(),
          uiOutput("learner_status")
        ),

        div(class="card",
          h4("Export"),
          actionButton("export_png", "\U0001F4BE Export Report PNG",
                       class = "btn export-btn"),
          tags$div(style="font-size:11px; color:#888; margin-top:6px",
            "Saves Tab 2+3+4 to PNG in results/demo_exports/")
        )
      ),

      # ── Main (9/12) ────────────────────────────────────────────────────
      column(9,
        tabsetPanel(id="main_tabs", type="tabs",

          tabPanel("1. Dataset Overview",
            div(class="tab-content", uiOutput("tab_overview"))),

          tabPanel("2. Quantitative Comparison",
            div(class="tab-content", uiOutput("tab_compare"))),

          tabPanel("3. Uplift / Qini Curves",
            div(class="tab-content", uiOutput("tab_curves"))),

          tabPanel("4. Customer Decision",
            div(class="tab-content", uiOutput("tab_decision"))),

          tabPanel("5. Upload CSV",
            div(class="tab-content", uiOutput("tab_upload_info")))
        )
      )
    )
  )
)

# ── Server ───────────────────────────────────────────────────────────────────

server <- function(input, output, session) {
  options(shiny.maxRequestSize = 200 * 1024^2)

  results_rv           <- reactiveVal(NULL)
  selected_customer_rv <- reactiveVal(NULL)
  learner_status_rv    <- reactiveVal(setNames(rep("pend", 6), LEARNER_ORDER))

  # ── Dynamic sidebar inputs ────────────────────────────────────────────────

  output$outcome_selector <- renderUI({
    ds <- input$dataset
    if (ds == "upload") return(NULL)
    out <- DATASETS[[ds]]$outcomes
    if (is.null(out)) return(NULL)
    choices_vec <- setNames(names(out), unname(out))
    selectInput("outcome", "Outcome:", choices = choices_vec,
                selected = names(out)[1], width = "100%")
  })

  output$dataset_desc <- renderText({ DATASETS[[input$dataset]]$desc %||% "" })

  output$eta_display <- renderUI({
    nt <- input$num_trees %||% 500
    n_train <- if (input$dataset == "hillstrom") 34000L else 80000L
    est <- round((n_train / 10000) * (nt / 500) * 20)  # 6 learners total
    div(style="font-size:12px; color:#888; margin-top:-6px; margin-bottom:6px",
        sprintf("Est. full train: ~%ds (all 6 learners)", est))
  })

  output$train_btn_ui <- renderUI({
    res <- results_rv()
    label <- if (is.null(res) || isTRUE(res$mode == "pretrained")) {
      "▶ Re-train with current settings"
    } else {
      "↻ Re-train"
    }
    actionButton("train_btn", label, class = "btn run-btn")
  })

  output$learner_status <- renderUI({
    st <- learner_status_rv()
    tagList(
      tags$div(style="font-size:11px; color:#888; margin-bottom:4px",
        "Learner status:"),
      lapply(LEARNER_ORDER, function(nm) {
        cls <- switch(st[[nm]],
                      ok   = "ls-ok",
                      fail = "ls-fail",
                      "ls-pend")
        icon <- switch(st[[nm]], ok = "✅", fail = "❌", "⏳")
        tags$span(class = paste("learner-status", cls),
                  paste(icon, LEARNER_LABELS[[nm]]))
      })
    )
  })

  # ── Upload CSV column detectors ──────────────────────────────────────────

  upload_preview <- reactive({
    req(input$csv_file)
    tryCatch(read.csv(input$csv_file$datapath, nrows = 2000),
             error = function(e) NULL)
  })

  output$upload_col_selectors <- renderUI({
    df <- upload_preview()
    req(!is.null(df))
    cols <- detect_columns(df)
    tagList(
      selectInput("upload_W", "Treatment (W):",
                  choices = names(df), selected = cols$W),
      selectInput("upload_Y", "Outcome (Y):",
                  choices = cols$numeric_cols, selected = cols$Y),
      checkboxGroupInput("upload_X", "Features (X):",
                         choices  = names(df), selected = cols$X)
    )
  })

  # ── Pretrained loader ─────────────────────────────────────────────────────

  last_loaded_key <- reactiveVal(NULL)

  pretrained_path <- reactive({
    ds <- input$dataset
    if (ds == "upload") return(NULL)
    key <- if (ds == "hillstrom") {
      pretrain_key("hillstrom", input$hillstrom_group %||% "men",
                   input$outcome %||% "visit")
    } else {
      pretrain_key(ds, NULL, input$outcome %||% "visit")
    }
    file.path(PRETRAIN_DIR, paste0(key, ".rds"))
  })

  observe({
    path <- pretrained_path()
    if (is.null(path)) return()
    if (file.exists(path) && (is.null(last_loaded_key()) || last_loaded_key() != path)) {
      t0 <- Sys.time()
      res <- tryCatch(readRDS(path), error = function(e) NULL)
      if (!is.null(res)) {
        res$mode <- "pretrained"
        results_rv(res)
        st <- sapply(LEARNER_ORDER, function(nm) {
          if (!is.null(res$learners[[nm]]) && isTRUE(res$learners[[nm]]$ok)) "ok" else "fail"
        })
        learner_status_rv(st)
        load_ms <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000)
        showNotification(
          tags$span(tags$b("Pre-trained loaded"), tags$br(),
                    sprintf("%s · ready in %dms", basename(path), load_ms)),
          duration = 2.5, type = "message"
        )
        last_loaded_key(path)
      }
    } else if (!file.exists(path)) {
      last_loaded_key(NULL)
    }
  })

  # ── Train button ──────────────────────────────────────────────────────────

  observeEvent(input$train_btn, {
    ds      <- input$dataset
    group   <- input$hillstrom_group %||% "men"
    outcome <- input$outcome %||% NULL
    nt      <- input$num_trees %||% 500

    # Reset learner status
    learner_status_rv(setNames(rep("pend", 6), LEARNER_ORDER))

    upload_df <- NULL; upload_cols <- NULL
    if (ds == "upload") {
      req(input$csv_file, input$upload_W, input$upload_Y, length(input$upload_X) > 0)
      upload_df <- tryCatch(read.csv(input$csv_file$datapath),
                            error = function(e) {
                              showNotification(conditionMessage(e),
                                               type = "error", duration = 8)
                              NULL
                            })
      req(!is.null(upload_df))
      upload_cols <- list(W = input$upload_W, Y = input$upload_Y, X = input$upload_X)
    }

    notif_id <- showNotification(
      tags$span(tags$b("Training 6 learners..."), tags$br(),
                "Step 0/7 — loading data"),
      duration = NULL, type = "message", closeButton = FALSE
    )

    progress_fn <- function(i, total, lbl) {
      st <- learner_status_rv()
      st[LEARNER_ORDER[i]] <- "pend"
      learner_status_rv(st)
      removeNotification(notif_id)
      assign("notif_id",
             showNotification(
               tags$span(tags$b(sprintf("Training %d/%d", i, total)),
                         tags$br(), lbl),
               duration = NULL, type = "message", closeButton = FALSE),
             envir = parent.frame())
    }

    res <- tryCatch(
      build_results(ds, group, outcome, nt, upload_df, upload_cols,
                    progress_fn = NULL),  # disable per-step notif to keep simple
      error = function(e) {
        removeNotification(notif_id)
        showNotification(paste("Training failed:", conditionMessage(e)),
                         type = "error", duration = 10)
        NULL
      }
    )
    req(!is.null(res))

    res$mode <- "fresh"
    results_rv(res)
    st <- sapply(LEARNER_ORDER, function(nm) {
      if (!is.null(res$learners[[nm]]) && isTRUE(res$learners[[nm]]$ok)) "ok" else "fail"
    })
    learner_status_rv(st)

    removeNotification(notif_id)
    showNotification(
      sprintf("Done! Trained in %.1fs total. n_test = %s",
              sum(sapply(res$learners, function(x) x$train_time %||% 0)),
              scales::comma(res$n_test)),
      duration = 5, type = "message"
    )
    selected_customer_rv(NULL)
  })

  # ── Mode badge ────────────────────────────────────────────────────────────

  output$mode_badge <- renderUI({
    res <- results_rv()
    if (is.null(res)) {
      return(tagList(
        span(class = "badge-none", "No model loaded"),
        div(style="font-size:11px; color:#999; margin-top:4px",
            "Click \"Re-train\" to start")
      ))
    }
    n_total <- scales::comma(res$n_train + res$n_test)
    if (res$mode == "pretrained") {
      tagList(
        span(class="badge-pre", sprintf("\U0001F512 Pre-trained · %s obs", n_total)),
        div(style="font-size:10px; color:#888; margin-top:4px",
            sprintf("Trained: %s", format(res$trained_at, "%Y-%m-%d %H:%M")))
      )
    } else {
      tagList(
        span(class="badge-fresh", sprintf("⚡ Fresh train · %s obs", n_total)),
        div(style="font-size:10px; color:#888; margin-top:4px",
            sprintf("Trained: %s", format(res$trained_at, "%Y-%m-%d %H:%M")))
      )
    }
  })

  # ─────────────────────────────────────────────────────────────────────────
  # TAB 1 — Dataset Overview
  # ─────────────────────────────────────────────────────────────────────────

  output$tab_overview <- renderUI({
    res <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg",
      "Click 'Re-train' in the sidebar to load data and train all 6 learners."))

    n_total <- res$n_train + res$n_test
    n_features <- length(res$X_cols)
    ratio_w1   <- mean(c(res$W_train, res$W_test) == 1)
    base_rate  <- mean(c(res$Y_train, res$Y_test))
    base_rate_label <- if (res$is_binary_Y) sprintf("%.2f%%", base_rate * 100)
                       else sprintf("%.3f", base_rate)

    tagList(
      fluidRow(
        column(5,
          div(class="card",
            h4("Dataset Info"),
            tags$ul(style="line-height:1.9; font-size:13px; padding-left:20px; margin:0",
              tags$li(tags$b("Name: "), res$dataset_label,
                      if (!is.null(res$group)) sprintf(" (%s group)", res$group)),
              tags$li(tags$b("Size: "), sprintf("%s samples × %d features",
                                                scales::comma(n_total), n_features)),
              tags$li(tags$b("Treatment (W): "),
                      sprintf("binary, %.1f%% treated", ratio_w1 * 100)),
              tags$li(tags$b("Outcome (Y): "), res$outcome_label,
                      tags$br(),
                      tags$span(style="color:#888; font-size:12px",
                                sprintf("Baseline rate: %s", base_rate_label))),
              tags$li(tags$b("Train/Test split: "),
                      sprintf("%s / %s (80/20, seed=42)",
                              scales::comma(res$n_train), scales::comma(res$n_test)))
            )
          ),
          div(class="card",
            h4("Baselines"),
            tags$ul(style="line-height:1.7; font-size:13px; padding-left:20px; margin:0",
              lapply(LEARNER_ORDER, function(nm) {
                tags$li(tags$b(LEARNER_LABELS[[nm]]),
                        if (nm == "causal_forest") tags$span(style="color:#2166ac", " ← main method"))
              })
            )
          )
        ),
        column(7,
          div(class="card",
            h4("Treatment vs Control Counts"),
            plotlyOutput("plot_w_dist", height = "220px")
          ),
          div(class="card",
            h4(sprintf("Outcome distribution by W (%s)", res$outcome_label)),
            plotlyOutput("plot_y_by_w", height = "280px")
          )
        )
      )
    )
  })

  output$plot_w_dist <- renderPlotly({
    res <- results_rv(); req(!is.null(res))
    W_all <- c(res$W_train, res$W_test)
    df <- data.frame(W = factor(W_all, levels = c(0, 1),
                                 labels = c("Control (W=0)", "Treated (W=1)")))
    counts <- as.data.frame(table(df$W))
    colnames(counts) <- c("Group", "Count")
    p <- ggplot(counts, aes(x = Group, y = Count, fill = Group,
                            text = paste0(Group, ": ", scales::comma(Count),
                                          " (", round(100 * Count / sum(Count), 1), "%)"))) +
      geom_col(width = 0.6, show.legend = FALSE) +
      scale_fill_manual(values = c("#95a5a6", "#27ae60")) +
      scale_y_continuous(labels = scales::comma) +
      labs(x = NULL, y = "Count") +
      theme_bw(base_size = 11) +
      theme(panel.grid.major.x = element_blank(),
            panel.grid.minor = element_blank(),
            legend.position = "none")
    ggplotly(p, tooltip = "text") %>%
      style_plotly(legend_pos = "none", margin_t = 20, margin_b = 50)
  })

  output$plot_y_by_w <- renderPlotly({
    res <- results_rv(); req(!is.null(res))
    W_all <- c(res$W_train, res$W_test)
    Y_all <- c(res$Y_train, res$Y_test)
    df <- data.frame(W = factor(W_all, levels = c(0,1),
                                labels = c("Control","Treated")),
                     Y = Y_all)
    if (res$is_binary_Y) {
      tab <- df %>% group_by(W) %>%
        summarise(rate = mean(Y), n = n(), .groups = "drop")
      tab$rate_pct <- sprintf("%.2f%%", tab$rate * 100)
      p <- ggplot(tab, aes(x = W, y = rate, fill = W,
                           text = paste0(W, ": ", rate_pct, " (n=",
                                         scales::comma(n), ")"))) +
        geom_col(width = 0.6, show.legend = FALSE) +
        scale_fill_manual(values = c("Control" = "#95a5a6", "Treated" = "#27ae60")) +
        scale_y_continuous(labels = scales::percent_format(accuracy = 0.01)) +
        labs(x = NULL, y = "Outcome rate (Y = 1)") +
        theme_bw(base_size = 11) +
        theme(panel.grid.major.x = element_blank(),
              panel.grid.minor = element_blank(),
              legend.position = "none")
      ggplotly(p, tooltip = "text") %>%
        style_plotly(legend_pos = "none", margin_t = 20, margin_b = 50)
    } else {
      df_small <- df[sample(nrow(df), min(nrow(df), 5000)), ]
      p <- ggplot(df_small, aes(x = Y, fill = W)) +
        geom_density(alpha = 0.55, color = "white", linewidth = 0.3) +
        scale_fill_manual(values = c("Control" = "#95a5a6", "Treated" = "#27ae60")) +
        labs(x = "Y", y = "Density", fill = NULL) +
        theme_bw(base_size = 11) +
        theme(panel.grid.minor = element_blank(),
              legend.position = "none")
      ggplotly(p, tooltip = c("x", "y", "fill")) %>%
        style_plotly(legend_pos = "bottom", margin_t = 20, margin_b = 70)
    }
  })

  # ─────────────────────────────────────────────────────────────────────────
  # TAB 2 — Quantitative Comparison
  # ─────────────────────────────────────────────────────────────────────────

  output$tab_compare <- renderUI({
    res <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg",
      "Train the models first to see comparison."))
    tagList(
      div(class="card",
        h4("Performance comparison across uplift methods"),
        DT::DTOutput("table_compare")
      ),
      div(class="card",
        h4("AUUC Comparison (higher = better)"),
        plotlyOutput("plot_auuc_bar", height = "360px")
      )
    )
  })

  output$table_compare <- DT::renderDT({
    res <- results_rv(); req(!is.null(res))
    df <- res$metrics
    out <- data.frame(
      Method = df$method,
      AUUC   = ifelse(is.na(df$auuc), "—", sprintf("%.4f", df$auuc)),
      Qini   = ifelse(is.na(df$qini), "—", sprintf("%.4f", df$qini)),
      AUC    = ifelse(is.na(df$auc),  "—", sprintf("%.4f", df$auc)),
      Train  = sprintf("%.1fs", df$train_time),
      stringsAsFactors = FALSE
    )
    colnames(out) <- c("Method", "AUUC \u2191", "Qini \u2191", "AUC (Y)", "Train")
    cf_row <- which(out$Method == "Causal Forest")
    DT::datatable(out, rownames = FALSE, selection = "none",
                  options = list(dom = 't', pageLength = 10, ordering = FALSE,
                                 columnDefs = list(
                                   list(className = 'dt-center', targets = 1:4)))) %>%
      DT::formatStyle("Method",
        target = "row",
        fontWeight = DT::styleEqual("Causal Forest", "bold"),
        backgroundColor = DT::styleEqual("Causal Forest", "#dbe9f6"),
        color = DT::styleEqual("Causal Forest", "#2166ac"))
  }, server = FALSE)

  output$plot_auuc_bar <- renderPlotly({
    res <- results_rv(); req(!is.null(res))
    df <- res$metrics
    df <- df[!is.na(df$auuc), ]
    if (nrow(df) == 0) return(plotly_empty() %>% layout(title="No AUUC available"))
    df$method <- factor(df$method, levels = df$method[order(df$auuc)])
    df$is_cf  <- df$method == "Causal Forest"
    p <- ggplot(df, aes(y = method, x = auuc, fill = method,
                        text = paste0(method, ": ", round(auuc, 4)))) +
      geom_col(show.legend = FALSE) +
      scale_fill_manual(values = LEARNER_COLORS) +
      labs(x = "AUUC", y = NULL) +
      theme_bw(base_size = 12) +
      theme(panel.grid.minor = element_blank(),
            panel.grid.major.y = element_blank(),
            legend.position = "none")
    ggplotly(p, tooltip = "text") %>%
      style_plotly(legend_pos = "none",
                   margin_l = 150, margin_r = 30,
                   margin_t = 20, margin_b = 50)
  })

  # ─────────────────────────────────────────────────────────────────────────
  # TAB 3 — Uplift / Qini Curves
  # ─────────────────────────────────────────────────────────────────────────

  output$tab_curves <- renderUI({
    res <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg",
      "Train the models first to see curves."))
    # methods that have valid tau_hat
    valid <- LEARNER_LABELS[setdiff(LEARNER_ORDER, "standard_clf")]
    tagList(
      fluidRow(
        column(8,
          checkboxGroupInput("curve_methods", "Show methods:",
            choices = unname(valid), selected = unname(valid), inline = TRUE),
          plotlyOutput("plot_uplift_curve", height = "400px"),
          br(),
          plotlyOutput("plot_qini_curve", height = "400px")
        ),
        column(4,
          div(class="card",
            h4("Key Observations"),
            uiOutput("key_observations")
          ),
          div(class="card",
            h4("Takeaway"),
            div(style="font-size:13px; line-height:1.6; color:#444",
                uiOutput("takeaway"))
          )
        )
      )
    )
  })

  uplift_data_all <- reactive({
    res <- results_rv(); req(!is.null(res))
    valid_lr <- setdiff(LEARNER_ORDER, "standard_clf")
    dfs <- lapply(valid_lr, function(nm) {
      lr <- res$learners[[nm]]
      if (!isTRUE(lr$ok)) return(NULL)
      d <- uplift_curve_data(lr$pred$tau_hat, res$W_test, res$Y_test)
      if (nrow(d) == 0) return(NULL)
      d$method <- LEARNER_LABELS[[nm]]
      d
    })
    dfs <- dfs[!sapply(dfs, is.null)]
    if (length(dfs) == 0) return(NULL)
    do.call(rbind, dfs)
  })

  output$plot_uplift_curve <- renderPlotly({
    df_all <- uplift_data_all(); req(!is.null(df_all))
    sel <- input$curve_methods %||% unique(df_all$method)
    df <- df_all[df_all$method %in% sel, ]
    if (nrow(df) == 0) return(plotly_empty())
    df <- df[order(df$method, df$pct_targeted), ]
    rand_df <- df_all %>% group_by(pct_targeted) %>%
      summarise(random = mean(random), .groups = "drop")

    p <- ggplot(df, aes(x = pct_targeted, y = cum_gain,
                        color = method, group = method)) +
      geom_line(linewidth = 1.1) +
      geom_line(data = rand_df, aes(x = pct_targeted, y = random),
                color = "#999999", linetype = "dashed", linewidth = 0.7,
                inherit.aes = FALSE) +
      scale_color_manual(values = LEARNER_COLORS, name = NULL) +
      scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
      labs(x = "% Population targeted", y = "Cumulative uplift gain") +
      theme_bw(base_size = 12) +
      theme(legend.position = "none",
            panel.grid.minor = element_blank())
    ggplotly(p, tooltip = c("colour", "x", "y")) %>%
      style_plotly(title = "Uplift Curve  (gray dashed = Random baseline)",
                   legend_pos = "bottom",
                   margin_t = 60, margin_b = 110, margin_l = 70, margin_r = 30)
  })

  qini_data_all <- reactive({
    res <- results_rv(); req(!is.null(res))
    valid_lr <- setdiff(LEARNER_ORDER, "standard_clf")
    dfs <- lapply(valid_lr, function(nm) {
      lr <- res$learners[[nm]]
      if (!isTRUE(lr$ok)) return(NULL)
      d <- qini_curve_data(lr$pred$tau_hat, res$W_test, res$Y_test)
      if (nrow(d) == 0) return(NULL)
      d$method <- LEARNER_LABELS[[nm]]
      d
    })
    dfs <- dfs[!sapply(dfs, is.null)]
    if (length(dfs) == 0) return(NULL)
    do.call(rbind, dfs)
  })

  output$plot_qini_curve <- renderPlotly({
    df_all <- qini_data_all(); req(!is.null(df_all))
    sel <- input$curve_methods %||% unique(df_all$method)
    df <- df_all[df_all$method %in% sel, ]
    if (nrow(df) == 0) return(plotly_empty())
    df <- df[order(df$method, df$pct_targeted), ]
    rand_df <- df_all %>% group_by(pct_targeted) %>%
      summarise(random = mean(random), .groups = "drop")

    p <- ggplot(df, aes(x = pct_targeted, y = qini_gain,
                        color = method, group = method)) +
      geom_line(linewidth = 1.1) +
      geom_line(data = rand_df, aes(x = pct_targeted, y = random),
                color = "#999999", linetype = "dashed", linewidth = 0.7,
                inherit.aes = FALSE) +
      scale_color_manual(values = LEARNER_COLORS, name = NULL) +
      scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
      labs(x = "% Population targeted", y = "Qini gain") +
      theme_bw(base_size = 12) +
      theme(legend.position = "none",
            panel.grid.minor = element_blank())
    ggplotly(p, tooltip = c("colour", "x", "y")) %>%
      style_plotly(title = "Qini Curve  (gray dashed = Random baseline)",
                   legend_pos = "bottom",
                   margin_t = 60, margin_b = 110, margin_l = 70, margin_r = 30)
  })

  output$key_observations <- renderUI({
    res <- results_rv(); req(!is.null(res))
    m <- res$metrics[!is.na(res$metrics$auuc), ]
    if (nrow(m) == 0) return(div("No AUUC available."))
    best <- m$method[which.max(m$auuc)]
    worst <- m$method[which.min(m$auuc)]
    # Sleeping dogs: customers with tau_hat < 0 (using CF)
    cf_lr <- res$learners$causal_forest
    sleeping_dogs <- if (!is.null(cf_lr) && isTRUE(cf_lr$ok)) {
      sum(cf_lr$pred$tau_hat < 0)
    } else NA
    sleeping_pct <- if (!is.na(sleeping_dogs)) {
      round(100 * sleeping_dogs / res$n_test, 1)
    } else NA

    tags$ol(style="padding-left:18px; font-size:13px; line-height:1.7; margin:0",
      tags$li(tags$b(best), " has the highest AUUC (",
              round(max(m$auuc), 4), ")"),
      tags$li(sprintf("%s has the lowest AUUC (%.4f) — baseline reference.",
                      worst, min(m$auuc))),
      if (!is.na(sleeping_dogs)) {
        tags$li(sprintf("\"Sleeping dogs\" detected: %s customers (%.1f%%) have τ̂ < 0 by Causal Forest.",
                        scales::comma(sleeping_dogs), sleeping_pct))
      }
    )
  })

  output$takeaway <- renderUI({
    res <- results_rv(); req(!is.null(res))
    m <- res$metrics[!is.na(res$metrics$auuc), ]
    if (nrow(m) == 0) return(div("—"))
    best <- m$method[which.max(m$auuc)]
    if (best == "Causal Forest") {
      "Causal Forest is the best-performing learner here. Use it to identify whom to target, and especially whom to exclude (sleeping dogs)."
    } else {
      sprintf("%s wins this benchmark on AUUC — a strong baseline; Causal Forest still provides paper-grade confidence intervals.",
              best)
    }
  })

  # ─────────────────────────────────────────────────────────────────────────
  # TAB 4 — Customer Decision
  # ─────────────────────────────────────────────────────────────────────────

  cf_pred <- reactive({
    res <- results_rv(); req(!is.null(res))
    lr <- res$learners$causal_forest
    req(!is.null(lr) && isTRUE(lr$ok))
    lr$pred
  })

  customer_table <- reactive({
    res <- results_rv(); req(!is.null(res))
    pred <- cf_pred()
    df <- as.data.frame(res$X_test)
    if (length(res$X_cols) == ncol(df)) colnames(df) <- res$X_cols
    df$W <- res$W_test
    df$Y <- res$Y_test
    df$tau_hat   <- round(pred$tau_hat, 4)
    df$CI_lower  <- round(pred$ci_lower, 4)
    df$CI_upper  <- round(pred$ci_upper, 4)
    df$id <- seq_len(nrow(df))
    df
  })

  output$tab_decision <- renderUI({
    res <- results_rv()
    if (is.null(res)) return(div(class="no-data-msg",
      "Train the models first to enable customer decision."))
    fluidRow(
      column(6,
        tabsetPanel(id="decision_picker", type="pills",
          tabPanel("Browse",
            br(),
            tags$p(style="font-size:12px; color:#666",
              "Click any row to load that customer in the decision panel →"),
            DT::DTOutput("dt_browse")
          ),
          tabPanel("Random",
            br(),
            tags$p(style="font-size:13px; color:#444",
              "Pick a random customer from the test set."),
            actionButton("random_pick", "\U0001F3B2 Pick Random Customer",
                         class = "btn run-btn", style = "width:auto; padding:10px 24px"),
            br(), br(),
            uiOutput("random_pick_summary")
          ),
          tabPanel("Top N",
            br(),
            sliderInput("top_n", "Show top N (by |τ̂|):",
              min = 5, max = 500, value = 20, step = 5, width = "100%"),
            DT::DTOutput("dt_topn")
          )
        )
      ),
      column(6,
        uiOutput("decision_panel")
      )
    )
  })

  output$dt_browse <- DT::renderDT({
    df <- customer_table()
    feat_cols <- setdiff(colnames(df), c("id","W","Y","tau_hat","CI_lower","CI_upper"))
    display <- df[, c("id", feat_cols, "W", "Y", "tau_hat", "CI_lower", "CI_upper")]
    DT::datatable(display, selection = "single", rownames = FALSE,
                  options = list(pageLength = 10, scrollX = TRUE, dom = 'tip')) %>%
      DT::formatStyle("tau_hat",
        color = DT::styleInterval(c(-0.01, 0.01),
                                  c("#e74c3c", "#888", "#27ae60")),
        fontWeight = "bold")
  }, server = TRUE)

  observeEvent(input$dt_browse_rows_selected, {
    sel <- input$dt_browse_rows_selected
    if (length(sel) > 0) selected_customer_rv(sel)
  })

  observeEvent(input$random_pick, {
    res <- results_rv(); req(!is.null(res))
    selected_customer_rv(sample.int(res$n_test, 1))
  })

  output$random_pick_summary <- renderUI({
    sel <- selected_customer_rv()
    if (is.null(sel)) return(tags$p(style="color:#999", "No customer picked yet."))
    df <- customer_table()
    row <- df[sel, ]
    tags$div(style="font-size:13px; color:#444",
      sprintf("Last pick: customer #%d · τ̂ = %.4f · W=%d · Y=%g",
              row$id, row$tau_hat, row$W, row$Y))
  })

  output$dt_topn <- DT::renderDT({
    df <- customer_table()
    n  <- min(input$top_n %||% 20, nrow(df))
    df_sorted <- df[order(abs(df$tau_hat), decreasing = TRUE), ][seq_len(n), ]
    feat_cols <- setdiff(colnames(df_sorted),
                         c("id","W","Y","tau_hat","CI_lower","CI_upper"))
    display <- df_sorted[, c("id", feat_cols, "W", "Y", "tau_hat", "CI_lower", "CI_upper")]
    DT::datatable(display, selection = "single", rownames = FALSE,
                  options = list(pageLength = 10, scrollX = TRUE, dom = 'tip')) %>%
      DT::formatStyle("tau_hat",
        color = DT::styleInterval(c(-0.01, 0.01),
                                  c("#e74c3c", "#888", "#27ae60")),
        fontWeight = "bold")
  }, server = TRUE)

  observeEvent(input$dt_topn_rows_selected, {
    sel <- input$dt_topn_rows_selected
    if (length(sel) > 0) {
      df <- customer_table()
      n  <- min(input$top_n %||% 20, nrow(df))
      df_sorted <- df[order(abs(df$tau_hat), decreasing = TRUE), ][seq_len(n), ]
      selected_customer_rv(df_sorted$id[sel])
    }
  })

  output$decision_panel <- renderUI({
    sel <- selected_customer_rv()
    res <- results_rv()
    if (is.null(sel) || is.null(res)) {
      return(div(class="card",
        div(class="no-data-msg",
          tags$div(style="font-size:32px", "\U0001F464"),
          tags$br(),
          "Select a customer from the left panel to see decision recommendation."
        )))
    }
    pred <- cf_pred()
    tau <- pred$tau_hat[sel]
    lower <- pred$ci_lower[sel]
    upper <- pred$ci_upper[sel]
    tagList(
      div(class="card",
        h4("Decision Threshold"),
        sliderInput("decision_threshold",
                    "TREAT if τ̂ > threshold AND CI_lower > 0:",
                    min = -0.2, max = 0.2, value = 0.0, step = 0.01, width = "100%"),
        uiOutput("decision_rule_text")
      ),
      div(class="card",
        uiOutput("customer_summary")
      ),
      div(class="card",
        h4("Feature values"),
        tableOutput("customer_features")
      ),
      div(class="card",
        h4("Feature contribution to \u03C4\u0302 (approximate)"),
        tags$p(style="font-size:11px; color:#888; margin-top:-6px",
          "Deviation from population mean \u00D7 variable importance. Green = pushes \u03C4\u0302 up, red = down."),
        plotlyOutput("plot_feature_contrib", height = "260px")
      ),
      div(class="card",
        h4("Population comparison"),
        uiOutput("population_compare"),
        plotlyOutput("plot_tau_position", height = "240px")
      )
    )
  })

  output$decision_rule_text <- renderUI({
    thr <- input$decision_threshold %||% 0
    tags$div(style="font-size:12px; color:#666; margin-top:-8px",
      sprintf("Current threshold: %.2f. A customer is recommended TREAT only if estimated uplift exceeds threshold AND the lower bound of 95%% CI is positive (statistical confidence).", thr))
  })

  output$customer_summary <- renderUI({
    sel <- selected_customer_rv(); res <- results_rv(); req(!is.null(sel), !is.null(res))
    pred <- cf_pred()
    tau <- pred$tau_hat[sel]; lower <- pred$ci_lower[sel]; upper <- pred$ci_upper[sel]
    thr <- input$decision_threshold %||% 0
    treat <- tau > thr && !is.na(lower) && lower > 0

    tau_class <- if (tau > 0) "pos-tau" else if (tau < 0) "neg-tau" else ""
    decision_class <- if (treat) "decision-treat" else "decision-no"
    decision_text  <- if (treat) "✅ TREAT" else "\U0001F6AB DO NOT TREAT"

    tagList(
      tags$div(style="text-align:center; color:#666; font-size:13px; text-transform:uppercase; letter-spacing:1px",
        sprintf("Customer #%d", sel)),
      tags$div(class = paste("tau-big", tau_class),
        sprintf("τ̂ = %.4f", tau)),
      tags$div(class="tau-ci",
        sprintf("95%% CI: [%.4f, %.4f]", lower, upper)),
      tags$div(class = decision_class, decision_text)
    )
  })

  output$customer_features <- renderTable({
    sel <- selected_customer_rv(); res <- results_rv(); req(!is.null(sel), !is.null(res))
    df <- customer_table()
    row <- df[sel, ]
    feat_cols <- setdiff(colnames(df), c("id","tau_hat","CI_lower","CI_upper"))
    out <- data.frame(
      Feature = feat_cols,
      Value   = sapply(feat_cols, function(c) {
        v <- row[[c]]
        if (is.numeric(v)) format(round(v, 3), nsmall = 0) else as.character(v)
      }),
      stringsAsFactors = FALSE
    )
    out
  }, striped = TRUE, hover = TRUE, bordered = TRUE, width = "100%", spacing = "xs")

  output$plot_feature_contrib <- renderPlotly({
    sel <- selected_customer_rv(); res <- results_rv()
    req(!is.null(sel), !is.null(res))
    vi <- res$var_importance
    req(!is.null(vi) && nrow(vi) > 0)
    # Customer feature vector and population stats
    cust_x <- as.numeric(res$X_test[sel, ])
    pop_mean <- colMeans(res$X_test)
    pop_sd   <- apply(res$X_test, 2, sd)
    pop_sd[pop_sd < 1e-8] <- 1  # avoid division by zero
    # Standardised deviation × variable importance = approximate contribution
    z_dev <- (cust_x - pop_mean) / pop_sd
    contrib <- z_dev * vi$importance
    df_c <- data.frame(
      feature = vi$feature,
      contribution = contrib,
      stringsAsFactors = FALSE
    )
    df_c <- df_c[order(abs(df_c$contribution), decreasing = TRUE), ]
    df_c$feature <- factor(df_c$feature, levels = rev(df_c$feature))
    df_c$direction <- ifelse(df_c$contribution >= 0, "Positive", "Negative")
    # Truncate long feature names so y-axis labels fit
    df_c$feature_label <- ifelse(nchar(as.character(df_c$feature)) > 22,
                                  paste0(substr(as.character(df_c$feature), 1, 20), "…"),
                                  as.character(df_c$feature))
    df_c$feature_label <- factor(df_c$feature_label, levels = df_c$feature_label)

    p <- ggplot(df_c, aes(x = contribution, y = feature_label, fill = direction,
                          text = paste0(feature, ": ", round(contribution, 4)))) +
      geom_col(show.legend = FALSE) +
      scale_fill_manual(values = c("Positive" = "#27ae60", "Negative" = "#e74c3c")) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "#888", linewidth = 0.5) +
      labs(x = "Contribution (approx.)", y = NULL) +
      theme_bw(base_size = 11) +
      theme(panel.grid.minor = element_blank(),
            panel.grid.major.y = element_blank(),
            legend.position = "none")
    ggplotly(p, tooltip = "text") %>%
      style_plotly(legend_pos = "none",
                   margin_l = 150, margin_r = 20,
                   margin_t = 20, margin_b = 50)
  })

  output$population_compare <- renderUI({
    sel <- selected_customer_rv(); res <- results_rv(); req(!is.null(sel), !is.null(res))
    pred <- cf_pred()
    tau <- pred$tau_hat[sel]
    pct <- mean(pred$tau_hat < tau) * 100
    tags$div(style="font-size:13px; color:#444; line-height:1.7",
      sprintf("This customer's τ̂ (%.4f) is higher than %.1f%% of the test population.", tau, pct),
      tags$br(),
      sprintf("Population mean τ̂ = %.4f · median = %.4f",
              mean(pred$tau_hat), median(pred$tau_hat))
    )
  })

  output$plot_tau_position <- renderPlotly({
    sel <- selected_customer_rv(); res <- results_rv(); req(!is.null(sel), !is.null(res))
    pred <- cf_pred()
    tau <- pred$tau_hat[sel]
    df <- data.frame(tau = pred$tau_hat)
    p <- ggplot(df, aes(x = tau)) +
      geom_density(fill = "#2166ac", alpha = 0.45, color = "white", linewidth = 0.4) +
      geom_vline(xintercept = tau, color = "#e74c3c", linewidth = 1.2) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "#888", linewidth = 0.6) +
      labs(x = "τ̂ value", y = NULL) +
      theme_bw(base_size = 11) +
      theme(panel.grid.minor = element_blank(),
            legend.position = "none")
    ggplotly(p) %>%
      style_plotly(title = "Customer position (red) vs population",
                   legend_pos = "none",
                   margin_t = 50, margin_b = 50, margin_l = 50, margin_r = 30)
  })

  # ─────────────────────────────────────────────────────────────────────────
  # TAB 5 — Upload CSV info
  # ─────────────────────────────────────────────────────────────────────────

  output$tab_upload_info <- renderUI({
    tagList(
      div(class="card",
        h4("How upload works"),
        tags$ol(style="line-height:1.8; font-size:13px; padding-left:20px",
          tags$li("Select \"Upload your own CSV\" in the sidebar dataset dropdown."),
          tags$li("Upload a CSV file (up to 200 MB). First 2,000 rows are previewed for column detection."),
          tags$li("Confirm or override the auto-detected W (treatment), Y (outcome), and X (features) columns."),
          tags$li("Click \"Re-train\". The 6 learners will train on your CSV (with an 80/20 train/test split, seed=42)."),
          tags$li("After training, all tabs update with your data. Use Tab 4 to look up individual customers.")
        ),
        tags$p(style="font-size:12px; color:#888; margin-top:12px",
          "Requirements: W must be 0/1 binary. Y can be 0/1 binary or continuous. X must have ≥2 columns.")
      )
    )
  })

  # ─────────────────────────────────────────────────────────────────────────
  # PNG export
  # ─────────────────────────────────────────────────────────────────────────

  observeEvent(input$export_png, {
    res <- results_rv()
    if (is.null(res)) {
      showNotification("Nothing to export — train models first.",
                       type = "warning", duration = 4)
      return()
    }
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    out_path <- file.path(EXPORT_DIR, sprintf("report_%s.png", ts))

    tryCatch({
      build_report_png(res, selected_customer_rv(),
                       input$decision_threshold %||% 0, out_path)
      showNotification(
        tags$span(tags$b("Report saved"), tags$br(),
                  tags$code(out_path)),
        duration = 6, type = "message"
      )
    }, error = function(e) {
      showNotification(paste("Export failed:", conditionMessage(e)),
                       type = "error", duration = 8)
    })
  })

}

# ── Report PNG builder (called from observeEvent above) ──────────────────────
build_report_png <- function(res, selected_customer, threshold, out_path) {
  if (!requireNamespace("gridExtra", quietly = TRUE)) {
    stop("gridExtra package required for PNG export.")
  }

  # Plot 1: table of metrics
  m <- res$metrics
  m_display <- data.frame(
    Method = m$method,
    AUUC   = ifelse(is.na(m$auuc), "—", sprintf("%.4f", m$auuc)),
    Qini   = ifelse(is.na(m$qini), "—", sprintf("%.4f", m$qini)),
    AUC    = ifelse(is.na(m$auc),  "—", sprintf("%.4f", m$auc)),
    Time   = sprintf("%.1fs", m$train_time),
    stringsAsFactors = FALSE
  )
  tbl_grob <- gridExtra::tableGrob(m_display, rows = NULL,
                                    theme = gridExtra::ttheme_minimal(
                                      base_size = 9,
                                      core = list(fg_params = list(hjust = 0, x = 0.05))))

  # Plot 2: AUUC bar
  bar_df <- m[!is.na(m$auuc), ]
  bar_df$method <- factor(bar_df$method, levels = bar_df$method[order(bar_df$auuc)])
  p_bar <- ggplot(bar_df, aes(y = method, x = auuc, fill = method)) +
    geom_col(show.legend = FALSE) +
    scale_fill_manual(values = LEARNER_COLORS) +
    labs(x = "AUUC", y = NULL, title = "AUUC Comparison") +
    theme_bw(base_size = 10) +
    theme(panel.grid.minor = element_blank())

  # Plot 3: uplift curve
  valid_lr <- setdiff(LEARNER_ORDER, "standard_clf")
  dfs <- lapply(valid_lr, function(nm) {
    lr <- res$learners[[nm]]
    if (!isTRUE(lr$ok)) return(NULL)
    d <- uplift_curve_data(lr$pred$tau_hat, res$W_test, res$Y_test)
    if (nrow(d) == 0) return(NULL)
    d$method <- LEARNER_LABELS[[nm]]
    d
  })
  curves_df <- do.call(rbind, dfs[!sapply(dfs, is.null)])
  rand_df <- curves_df %>% group_by(pct_targeted) %>%
    summarise(random = mean(random), .groups = "drop")
  p_curve <- ggplot(curves_df, aes(x = pct_targeted, y = cum_gain, color = method)) +
    geom_line(linewidth = 0.8) +
    geom_line(data = rand_df, aes(x = pct_targeted, y = random),
              color = "#999999", linetype = "dashed", linewidth = 0.6,
              inherit.aes = FALSE) +
    scale_color_manual(values = LEARNER_COLORS, name = NULL) +
    scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
    labs(x = "% Population targeted", y = "Cumulative gain",
         title = "Uplift Curve") +
    theme_bw(base_size = 10) +
    theme(legend.position = "bottom",
          panel.grid.minor = element_blank())

  # Plot 4 (optional): customer detail
  p_cust <- NULL
  if (!is.null(selected_customer)) {
    cf_lr <- res$learners$causal_forest
    if (!is.null(cf_lr) && isTRUE(cf_lr$ok)) {
      tau <- cf_lr$pred$tau_hat[selected_customer]
      lower <- cf_lr$pred$ci_lower[selected_customer]
      upper <- cf_lr$pred$ci_upper[selected_customer]
      treat <- tau > threshold && !is.na(lower) && lower > 0
      decision <- if (treat) "TREAT" else "DO NOT TREAT"
      dec_color <- if (treat) "#27ae60" else "#e74c3c"
      df_pos <- data.frame(tau = cf_lr$pred$tau_hat)
      p_cust <- ggplot(df_pos, aes(x = tau)) +
        geom_density(fill = "#2166ac", alpha = 0.4, color = "white") +
        geom_vline(xintercept = tau, color = "#e74c3c", linewidth = 1.2) +
        geom_vline(xintercept = 0, linetype = "dashed", color = "#888") +
        labs(x = "τ̂", y = NULL,
             title = sprintf("Customer #%d  ·  τ̂ = %.4f  ·  Decision: %s",
                             selected_customer, tau, decision)) +
        theme_bw(base_size = 10) +
        theme(plot.title = element_text(color = dec_color, face = "bold"),
              panel.grid.minor = element_blank())
    }
  }

  # Compose layout
  header <- gridExtra::tableGrob(
    data.frame(
      Info = c(sprintf("Dataset: %s", res$dataset_label),
               sprintf("Outcome: %s", res$outcome_label),
               sprintf("n_train = %s, n_test = %s",
                       scales::comma(res$n_train), scales::comma(res$n_test)),
               sprintf("Trained: %s", format(res$trained_at, "%Y-%m-%d %H:%M")))
    ), rows = NULL, cols = NULL,
    theme = gridExtra::ttheme_minimal(base_size = 9,
                                       core = list(fg_params = list(hjust = 0, x = 0.02))))

  plot_list <- if (is.null(p_cust)) {
    list(header, tbl_grob, p_bar, p_curve)
  } else {
    list(header, tbl_grob, p_bar, p_curve, p_cust)
  }
  layout_matrix <- if (is.null(p_cust)) {
    rbind(c(1, 1), c(2, 3), c(4, 4))
  } else {
    rbind(c(1, 1), c(2, 3), c(4, 5))
  }

  g <- gridExtra::arrangeGrob(grobs = plot_list, layout_matrix = layout_matrix,
                               top = grid::textGrob(
                                 "Causal Forest Live Demo Report",
                                 gp = grid::gpar(fontsize = 14, fontface = "bold")))
  ggsave(out_path, g, width = 14, height = 11, dpi = 130, bg = "white")
}

shinyApp(ui, server)
