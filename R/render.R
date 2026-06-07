required_packages <- c(
  "dplyr",
  "ggplot2",
  "knitr",
  "lubridate",
  "rmarkdown",
  "scales",
  "tibble",
  "tidyr",
  "tidyquant"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0) {
  stop(
    "Restore the project environment before rendering. Missing packages: ",
    paste(missing_packages, collapse = ", "),
    call. = FALSE
  )
}

dir.create("outputs", showWarnings = FALSE, recursive = TRUE)

rmarkdown::render(
  input = "report.Rmd",
  output_file = "report.html",
  output_dir = "outputs",
  envir = new.env(parent = globalenv())
)
