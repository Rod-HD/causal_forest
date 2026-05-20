# app.R — Shiny demo: Wager & Athey (2018) Simulation Results
# Run: Rscript -e "shiny::runApp('app.R', launch.browser=TRUE)"

suppressPackageStartupMessages({
  library(shiny)
  library(ggplot2)
  library(plotly)
  library(dplyr)
})

SD      <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")
RES_DIR <- file.path(SD, "..", "results")
source(file.path(SD, "dgp.R"))

# ── Static metadata ───────────────────────────────────────────────────────────

DESIGNS <- list(
  "1" = list(
    label   = "Design 1 — Confounding",
    methods = c("cf","knn10","knn100"),
    labels  = c("Causal Forest","10-NN","100-NN"),
    d_vals  = c(2,5,10,15,20,30),
    desc    = paste(
      "n = 500 · R = 500 replications · B = 1000 trees · subsample fraction = 0.10",
      "tau(x) = 0  (true treatment effect is zero everywhere)",
      "e(x) = 0.25 × (1 + Beta(2,4).pdf(x₁))  — confounded propensity",
      "m(x) = 2x₁ − 1  — strong baseline effect",
      "Goal: test ability to resist bias from correlation between e(x) and m(x).",
      "kNN: k = 10 and 100",
      sep = "\n"
    )
  ),
  "2" = list(
    label   = "Design 2 — Smooth Heterogeneity",
    methods = c("cf","knn7","knn50"),
    labels  = c("Causal Forest","7-NN","50-NN"),
    d_vals  = c(2,3,4,5,6,8),
    desc    = paste(
      "n = 5000 · R = 25 replications · B = 2000 trees · subsample fraction = 0.50",
      "tau(x) = sigma20(x₁) × sigma20(x₂)  where sigma20(x) = 1 + 1/(1+exp(-20(x-1/3)))",
      "e(x) = 0.5  (randomised experiment — no confounding)",
      "m(x) = 0",
      "Goal: test ability to adapt to smoothly heterogeneous treatment effects.",
      "kNN: k = 7 and 50",
      sep = "\n"
    )
  ),
  "3" = list(
    label   = "Design 3 — Sharp Heterogeneity",
    methods = c("cf","knn10","knn100"),
    labels  = c("Causal Forest","10-NN","100-NN"),
    d_vals  = c(2,3,4,5,6,8),
    desc    = paste(
      "n = 10000 · R = 40 replications · B = 10000 trees · subsample fraction = 0.20",
      "tau(x) = sigma12(x₁) × sigma12(x₂)  where sigma12(x) = 2/(1+exp(-12(x-0.5)))",
      "e(x) = 0.5  (randomised experiment — no confounding)",
      "m(x) = 0",
      "Goal: test ability to capture sharp peaks near x₁, x₂ ≈ 1.",
      "kNN: k = 10 and 100",
      sep = "\n"
    )
  )
)

COLORS <- c(
  "Causal Forest" = "#2166ac",
  "7-NN"  = "#d6604d", "10-NN" = "#d6604d",
  "50-NN" = "#f4a582", "100-NN"= "#b2182b"
)
SHAPES <- c(
  "Causal Forest"=16, "7-NN"=17, "10-NN"=17, "50-NN"=15, "100-NN"=15
)

# ── Data loader ───────────────────────────────────────────────────────────────

load_design_data <- function(design_key) {
  meta <- DESIGNS[[design_key]]
  do.call(rbind, lapply(seq_along(meta$methods), function(mi) {
    m  <- meta$methods[mi]
    lb <- meta$labels[mi]
    do.call(rbind, lapply(meta$d_vals, function(d) {
      fp <- file.path(RES_DIR, paste0("design", design_key),
                      sprintf("r_%s_d%d.csv", m, d))
      if (!file.exists(fp)) return(NULL)
      df <- read.csv(fp)
      data.frame(method = lb, d = d,
                 mse      = mean(df$mse),
                 coverage = mean(df$coverage),
                 se_mse   = sd(df$mse)      / sqrt(nrow(df)),
                 se_cov   = sd(df$coverage) / sqrt(nrow(df)))
    }))
  }))
}

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { background:#f5f6fa; font-family: 'Segoe UI', sans-serif; }
    .navbar { background:#2c3e50 !important; }
    h2 { color:#2c3e50; font-weight:700; margin-bottom:4px; }
    .subtitle { color:#777; font-size:14px; margin-bottom:20px; }
    .card { background:#fff; border-radius:8px; padding:18px 20px;
            box-shadow:0 1px 4px rgba(0,0,0,0.08); margin-bottom:16px; }
    .card h4 { color:#2c3e50; margin-top:0; font-weight:600; }
    .desc-box { background:#f0f4f8; border-left:4px solid #2166ac;
                border-radius:4px; padding:12px 15px; font-size:13px;
                white-space:pre-line; line-height:1.7; color:#444; }
    .stat-row { display:flex; gap:20px; flex-wrap:wrap; }
    .stat-item { background:#f0f4f8; border-radius:6px; padding:10px 16px;
                 min-width:100px; text-align:center; }
    .stat-val  { font-size:22px; font-weight:700; color:#2166ac; }
    .stat-lbl  { font-size:11px; color:#888; margin-top:2px; }
    .tab-content { background:#fff; border-radius:0 8px 8px 8px;
                   padding:20px; box-shadow:0 1px 4px rgba(0,0,0,0.08); }
    .nav-tabs > li.active > a { font-weight:600; color:#2166ac !important; }
  "))),

  div(style="padding:20px 30px",
    h2("Causal Forest Simulation"),
    div(class="subtitle",
        "Wager & Athey (2018) JASA — Reproduction using R packages ",
        code("grf"), " + ", code("FNN"), " · 54/54 cells completed"),

    fluidRow(
      # ── Sidebar ──────────────────────────────────────────────────────────
      column(3,
        div(class="card",
          h4("Design"),
          selectInput("design", NULL,
            choices = setNames(names(DESIGNS), sapply(DESIGNS, `[[`, "label")),
            selected = "1", width = "100%"),
          br(),
          div(class="desc-box", textOutput("design_desc"))
        ),
        div(class="card",
          h4("Methods"),
          checkboxGroupInput("methods", NULL,
            choices  = DESIGNS[["1"]]$labels,
            selected = DESIGNS[["1"]]$labels)
        )
      ),

      # ── Main panel ────────────────────────────────────────────────────────
      column(9,
        tabsetPanel(id="tabs", type="tabs",

          tabPanel("Comparison Chart",
            div(class="tab-content",
              br(),
              fluidRow(
                column(6, plotlyOutput("plot_mse",      height="340px")),
                column(6, plotlyOutput("plot_coverage", height="340px"))
              ),
              br(),
              div(style="font-size:12px; color:#888",
                "Hover over points for exact values · Toggle methods in sidebar")
            )
          ),

          tabPanel("ITE Distribution",
            div(class="tab-content",
              div(style="display:flex; align-items:center; gap:14px; padding:6px 0 14px; flex-wrap:wrap",
                tags$label(style="font-weight:600; color:#2c3e50; margin:0", "Dimension d:"),
                div(style="flex:1; min-width:240px", uiOutput("d_slider_ui"))
              ),
              fluidRow(
                column(8, plotlyOutput("plot_ite", height="380px")),
                column(4,
                  br(),
                  div(class="card",
                    h4("True CATE Stats"),
                    uiOutput("ite_stats")
                  ),
                  div(class="card",
                    h4("What is ITE?"),
                    tags$p(style="font-size:13px; color:#555; line-height:1.7",
                      "Individual Treatment Effect (ITE) = tau(X) = E[Y(1) - Y(0) | X].",
                      br(),
                      "This shows the distribution of true treatment effects across test points.",
                      br(), br(),
                      "Design 1: tau = 0 everywhere (no real effect).",
                      br(),
                      "Design 2/3: tau varies by individual covariates X₁, X₂."
                    )
                  )
                )
              )
            )
          ),

          tabPanel("Results Table",
            div(class="tab-content",
              br(),
              tableOutput("results_table"),
              div(style="font-size:12px; color:#888; margin-top:8px",
                "Values are mean ± MC standard error across replications. Target coverage = 0.95.")
            )
          )
        )
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  # Update checkboxes when design changes
  observeEvent(input$design, {
    meta <- DESIGNS[[input$design]]
    updateCheckboxGroupInput(session, "methods",
      choices  = meta$labels,
      selected = meta$labels)
  })

  output$d_slider_ui <- renderUI({
    d_vals <- DESIGNS[[input$design]]$d_vals
    radioButtons("d_ite", label = NULL,
                 choices  = setNames(d_vals, paste0("d = ", d_vals)),
                 selected = d_vals[2],
                 inline   = TRUE)
  })

  output$design_desc <- renderText({ DESIGNS[[input$design]]$desc })

  # Load and filter data
  data_all <- reactive({ load_design_data(input$design) })

  data_filtered <- reactive({
    req(input$methods)
    data_all() %>% filter(method %in% input$methods)
  })

  # ── Comparison plots ────────────────────────────────────────────────────────

  make_plot <- function(df, y_col, y_label, ref_line = FALSE) {
    p <- ggplot(df, aes(
      x     = d,
      y     = .data[[y_col]],
      color = method,
      shape = method,
      group = method,
      text  = paste0("Method: ", method,
                     "\nd = ", d,
                     "\n", y_label, ": ", round(.data[[y_col]], 4))
    )) +
      geom_line(linewidth = 0.9) +
      geom_point(size = 3) +
      scale_color_manual(values = COLORS, name = NULL) +
      scale_shape_manual(values = SHAPES, name = NULL) +
      labs(x = "Dimension d", y = y_label,
           title = paste(y_label, "vs Dimension d")) +
      theme_bw(base_size = 12) +
      theme(legend.position  = "bottom",
            panel.grid.minor = element_blank(),
            plot.title       = element_text(face = "bold", size = 12))

    if (ref_line)
      p <- p + geom_hline(yintercept = 0.95, linetype = "dashed",
                          color = "#e74c3c", linewidth = 0.7)
    ggplotly(p, tooltip = "text") %>%
      layout(legend = list(orientation="h", y=-0.3),
             margin = list(b=80))
  }

  output$plot_mse <- renderPlotly({
    df <- data_filtered()
    req(nrow(df) > 0)
    make_plot(df, "mse", "MSE")
  })

  output$plot_coverage <- renderPlotly({
    df <- data_filtered()
    req(nrow(df) > 0)
    make_plot(df, "coverage", "Coverage (95% CI)", ref_line = TRUE)
  })

  # ── ITE distribution ────────────────────────────────────────────────────────

  ite_tau <- reactive({
    req(input$d_ite)
    fn <- list("1"=gen_design1, "2"=gen_design2, "3"=gen_design3)[[input$design]]
    fn(4000, as.integer(input$d_ite), seed = 99)$tau
  })

  output$plot_ite <- renderPlotly({
    tau <- ite_tau()
    df  <- data.frame(tau = tau)
    subtitle <- paste0(
      DESIGNS[[input$design]]$label, "  ·  d = ", input$d_ite,
      "  ·  n = 4000 test points"
    )
    p <- ggplot(df, aes(x = tau)) +
      geom_density(fill = "#2166ac", alpha = 0.55, color = "white", linewidth = 0.4) +
      geom_vline(xintercept = mean(tau), linetype = "dashed",
                 color = "#e74c3c", linewidth = 0.9) +
      labs(title   = "True ITE (tau) Distribution",
           subtitle = subtitle,
           x = "tau(X)  —  True CATE",
           y = "Density") +
      theme_bw(base_size = 12) +
      theme(panel.grid.minor = element_blank(),
            plot.title    = element_text(face="bold", size=12),
            plot.subtitle = element_text(color="#666", size=11))
    ggplotly(p) %>% layout(margin = list(t=60))
  })

  output$ite_stats <- renderUI({
    tau <- ite_tau()
    div(class="stat-row",
      div(class="stat-item",
        div(class="stat-val", round(mean(tau), 3)),
        div(class="stat-lbl", "Mean")),
      div(class="stat-item",
        div(class="stat-val", round(sd(tau), 3)),
        div(class="stat-lbl", "SD")),
      div(class="stat-item",
        div(class="stat-val", round(min(tau), 3)),
        div(class="stat-lbl", "Min")),
      div(class="stat-item",
        div(class="stat-val", round(max(tau), 3)),
        div(class="stat-lbl", "Max"))
    )
  })

  # ── Results table ───────────────────────────────────────────────────────────

  output$results_table <- renderTable({
    data_all() %>%
      arrange(method, d) %>%
      transmute(
        Method   = method,
        d        = d,
        `MSE (mean ± SE)`      = sprintf("%.4f ± %.4f", mse, se_mse),
        `Coverage (mean ± SE)` = sprintf("%.3f ± %.3f", coverage, se_cov)
      )
  }, striped=TRUE, hover=TRUE, bordered=TRUE, width="100%")
}

shinyApp(ui, server)
