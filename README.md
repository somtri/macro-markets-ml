# Macro Signals and U.S. Equity Returns

[![Reproducibility check](https://github.com/somtri/macro-markets-ml/actions/workflows/render-report.yml/badge.svg)](https://github.com/somtri/macro-markets-ml/actions/workflows/render-report.yml)
[![R](https://img.shields.io/badge/R-4.5.1-276DC3?logo=r)](https://www.r-project.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A reproducible R case study testing whether unemployment and recent market behavior
help classify next-month S&P 500 direction.

[**View the hosted portfolio report**](https://somtri.github.io/macro-markets-ml/)

The project is designed as an honest forecasting exercise: macro observations are aligned
to when they would have been public, the model is evaluated on a chronological holdout,
and performance is compared with the market's historical positive-month rate.

## Key result

The release-aware logistic regression achieved **55.7% out-of-sample accuracy** and a
**0.49 ROC AUC**, compared with **68.9% accuracy** for the historical positive-month
baseline. The analysis therefore finds no useful next-month directional signal in this
small feature set. That negative result is reported directly rather than optimized away.

## View the analysis

- **Hosted report:** [somtri.github.io/macro-markets-ml](https://somtri.github.io/macro-markets-ml/)
- **Versioned report artifact:** [`outputs/report.html`](outputs/report.html)
- **Report source:** [`report.Rmd`](report.Rmd)
- **Analysis pipeline:** [`R/analysis.R`](R/analysis.R)

## What this project demonstrates

- retrieval and validation of market and macroeconomic time series;
- correct compounding of daily log returns into monthly returns;
- release-aware feature engineering to reduce look-ahead bias;
- train-only feature standardization and chronological validation;
- logistic regression with interpretable standardized coefficients;
- evaluation against a class-imbalance baseline using accuracy, balanced accuracy,
  Brier score, and ROC AUC;
- generated reporting, so metrics and conclusions stay consistent with the selected data.

## Update behavior

The hosted report is republished when changes are pushed to `main`; it does not update
continuously. Standard renders use the versioned snapshots in `data/raw`. To fetch newer
source data, run the explicit refresh command below and commit the updated snapshots.

## Research design

At the end of each month, the model uses the latest *published* unemployment rate,
its monthly change, the current S&P 500 monthly return, and annualized volatility.
The target is whether the following month's S&P 500 return is positive.

The unemployment feature is lagged because a month's official unemployment rate is
released during the next month. This is a deliberately conservative timing assumption.

## Repository structure

```text
.
|-- DESCRIPTION          # Declared R dependencies
|-- data/raw/             # Versioned source-data snapshots
|-- R/
|   |-- analysis.R       # Data, feature engineering, modeling, evaluation
|   `-- render.R         # Reproducible render entry point
|-- outputs/
|   `-- report.html      # Portfolio-ready rendered report
|-- report.Rmd           # Narrative and visualizations
|-- styles.css           # Report presentation layer
`-- renv.lock            # Package versions
```

## Reproduce the report

Install R and RStudio or Pandoc, then run from the project root:

```r
install.packages("renv")
renv::restore()
source("R/render.R")
```

The finished report is written to `outputs/report.html`.

To refresh the source-data snapshots before rendering:

```r
Sys.setenv(REFRESH_DATA = "true")
source("R/render.R")
```

If either upstream request fails, the pipeline falls back to the versioned snapshots.

## Data sources

- [Yahoo Finance: S&P 500 historical data](https://finance.yahoo.com/quote/%5EGSPC/history)
- [FRED: U.S. Unemployment Rate](https://fred.stlouisfed.org/series/UNRATE)

## Limitations

FRED data are latest-vintage rather than real-time vintage observations, and the model
is a research baseline rather than a trading strategy. The analysis does not model
transaction costs, position sizing, or economic significance.

## License

MIT
