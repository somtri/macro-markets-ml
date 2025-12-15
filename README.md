# Macro & Markets (R) — Returns, Unemployment, and a Simple ML Classifier

This project pulls real market and macroeconomic time-series data from the web, cleans and combines the data into a monthly dataset, visualizes key patterns, and trains a simple machine learning model to classify whether the S&P 500 return will be positive next month.

## What this repo contains

- `report.Rmd`: The full reproducible analysis and final report (data pull → cleaning → summaries → plots → ML).
- `renv.lock`: Locked package versions so the project runs the same for anyone.
- `R/`: (Optional) helper scripts if we split code out later.
- `outputs/`: saved figures and knitted report output.

## Data sources

- S&P 500 index data (ticker `^GSPC`) from Yahoo Finance, accessed via the `tidyquant` R package  
  Reference page: https://finance.yahoo.com/quote/%5EGSPC/history
- U.S. Unemployment Rate (FRED series `UNRATE`), accessed via the `tidyquant` R package  
  Reference page: https://fred.stlouisfed.org/series/UNRATE

## How to run (reproducible)

1. Clone this repository.
2. Open the project in RStudio (`macro-markets-ml.Rproj`).
3. Restore the exact package environment:

```r
renv::restore()
