analysis_start <- as.Date(params$analysis_start)
train_end <- as.Date(params$train_end)
last_complete_day <- floor_date(Sys.Date(), "month") - days(1)
last_complete_month <- floor_date(last_complete_day, "month")
refresh_data <- tolower(Sys.getenv("REFRESH_DATA", "false")) %in% c("1", "true", "yes")
sp500_cache_path <- file.path("data", "raw", "sp500_daily.csv")
unemployment_cache_path <- file.path("data", "raw", "unemployment_monthly.csv")

safe_ratio <- function(numerator, denominator) {
  ifelse(denominator == 0, NA_real_, numerator / denominator)
}

roc_auc <- function(actual, probability) {
  positives <- sum(actual == 1)
  negatives <- sum(actual == 0)

  if (positives == 0 || negatives == 0) {
    return(NA_real_)
  }

  probability_ranks <- rank(probability, ties.method = "average")
  (sum(probability_ranks[actual == 1]) - positives * (positives + 1) / 2) /
    (positives * negatives)
}

classification_metrics <- function(actual, probability, model_name, threshold = 0.5) {
  predicted <- as.integer(probability >= threshold)
  true_positive <- sum(actual == 1 & predicted == 1)
  true_negative <- sum(actual == 0 & predicted == 0)
  false_positive <- sum(actual == 0 & predicted == 1)
  false_negative <- sum(actual == 1 & predicted == 0)

  sensitivity <- safe_ratio(true_positive, true_positive + false_negative)
  specificity <- safe_ratio(true_negative, true_negative + false_positive)

  tibble(
    model = model_name,
    metric = c(
      "Accuracy",
      "Balanced accuracy",
      "Precision",
      "Recall",
      "Specificity",
      "Brier score",
      "ROC AUC"
    ),
    value = c(
      mean(predicted == actual),
      mean(c(sensitivity, specificity), na.rm = TRUE),
      safe_ratio(true_positive, true_positive + false_positive),
      sensitivity,
      specificity,
      mean((probability - actual)^2),
      roc_auc(actual, probability)
    )
  )
}

standardize_features <- function(data, centers, spreads) {
  output <- data

  for (feature in names(centers)) {
    output[[feature]] <- (output[[feature]] - centers[[feature]]) / spreads[[feature]]
  }

  output
}

validate_columns <- function(data, columns, label) {
  missing_columns <- setdiff(columns, names(data))

  if (length(missing_columns) > 0) {
    stop(
      sprintf("%s is missing required columns: %s", label, paste(missing_columns, collapse = ", ")),
      call. = FALSE
    )
  }

  if (nrow(data) == 0) {
    stop(sprintf("%s returned no rows.", label), call. = FALSE)
  }
}

read_sp500_cache <- function() {
  if (!file.exists(sp500_cache_path)) {
    stop("The S&P 500 cache is missing. Re-run with REFRESH_DATA=true.", call. = FALSE)
  }

  read.csv(sp500_cache_path, stringsAsFactors = FALSE) %>%
    mutate(date = as.Date(date))
}

read_unemployment_cache <- function() {
  if (!file.exists(unemployment_cache_path)) {
    stop("The unemployment cache is missing. Re-run with REFRESH_DATA=true.", call. = FALSE)
  }

  read.csv(unemployment_cache_path, stringsAsFactors = FALSE) %>%
    mutate(date = as.Date(date))
}

fetch_sp500 <- function() {
  suppressWarnings(
    tryCatch(
      tq_get(
        "^GSPC",
        from = analysis_start,
        to = last_complete_day + days(1),
        get = "stock.prices"
      ),
      error = function(error) NULL
    )
  )
}

fetch_unemployment <- function() {
  suppressWarnings(
    tryCatch(
      tq_get(
        "UNRATE",
        from = analysis_start,
        to = last_complete_day,
        get = "economic.data"
      ),
      error = function(error) NULL
    )
  )
}

sp500_candidate <- if (refresh_data) fetch_sp500() else NULL

if (
  is.data.frame(sp500_candidate) &&
    nrow(sp500_candidate) > 100 &&
    all(c("date", "adjusted") %in% names(sp500_candidate))
) {
  dir.create(dirname(sp500_cache_path), recursive = TRUE, showWarnings = FALSE)
  write.csv(sp500_candidate, sp500_cache_path, row.names = FALSE)
  sp500_raw <- sp500_candidate
  sp500_data_source <- "Live Yahoo Finance refresh"
} else {
  sp500_raw <- read_sp500_cache()
  sp500_data_source <- "Versioned Yahoo Finance snapshot"
}

sp500_raw <- sp500_raw %>%
  filter(date >= analysis_start, date <= last_complete_day)

validate_columns(sp500_raw, c("date", "adjusted"), "Yahoo Finance S&P 500 data")

if (any(!is.finite(sp500_raw$adjusted)) || any(sp500_raw$adjusted <= 0)) {
  stop("S&P 500 adjusted prices contain invalid values.", call. = FALSE)
}

sp500_daily <- sp500_raw %>%
  arrange(date) %>%
  mutate(daily_log_return = log(adjusted / lag(adjusted))) %>%
  filter(!is.na(daily_log_return))

sp500_monthly <- sp500_daily %>%
  mutate(month_date = floor_date(date, "month")) %>%
  group_by(month_date) %>%
  summarise(
    monthly_log_return = sum(daily_log_return),
    monthly_return = exp(monthly_log_return) - 1,
    annualized_volatility = sd(daily_log_return) * sqrt(252),
    n_trading_days = n(),
    .groups = "drop"
  ) %>%
  filter(month_date <= last_complete_month)

unemployment_candidate <- if (refresh_data) fetch_unemployment() else NULL

if (
  is.data.frame(unemployment_candidate) &&
    nrow(unemployment_candidate) > 24 &&
    all(c("date", "price") %in% names(unemployment_candidate))
) {
  dir.create(dirname(unemployment_cache_path), recursive = TRUE, showWarnings = FALSE)
  write.csv(unemployment_candidate, unemployment_cache_path, row.names = FALSE)
  unemp_raw <- unemployment_candidate
  unemployment_data_source <- "Live FRED refresh"
} else {
  unemp_raw <- read_unemployment_cache()
  unemployment_data_source <- "Versioned FRED snapshot"
}

validate_columns(unemp_raw, c("date", "price"), "FRED unemployment data")

unemp_monthly <- unemp_raw %>%
  transmute(
    date,
    unemployment_rate = price
  ) %>%
  arrange(date) %>%
  filter(date <= last_complete_month)

unemployment_features <- unemp_monthly %>%
  mutate(
    available_unemployment = unemployment_rate,
    available_unemp_change = unemployment_rate - lag(unemployment_rate),
    month_date = date %m+% months(1)
  ) %>%
  select(month_date, available_unemployment, available_unemp_change)

descriptive_data <- sp500_monthly %>%
  inner_join(unemp_monthly, by = c("month_date" = "date"))

model_data <- sp500_monthly %>%
  left_join(unemployment_features, by = "month_date") %>%
  arrange(month_date) %>%
  mutate(
    next_month_return = lead(monthly_return),
    next_month_up = as.integer(next_month_return > 0)
  ) %>%
  drop_na(
    available_unemployment,
    available_unemp_change,
    monthly_return,
    annualized_volatility,
    next_month_return
  )

feature_names <- c(
  "available_unemployment",
  "available_unemp_change",
  "monthly_return",
  "annualized_volatility"
)

train_data <- model_data %>%
  filter(month_date <= floor_date(train_end, "month"))

test_data <- model_data %>%
  filter(month_date > floor_date(train_end, "month"))

if (nrow(train_data) < 100 || nrow(test_data) < 24) {
  stop("The chronological split produced too few training or test observations.", call. = FALSE)
}

if (max(train_data$month_date) >= min(test_data$month_date)) {
  stop("Training and test periods overlap.", call. = FALSE)
}

feature_center <- vapply(train_data[feature_names], mean, numeric(1))
feature_scale <- vapply(train_data[feature_names], sd, numeric(1))

if (any(!is.finite(feature_scale)) || any(feature_scale == 0)) {
  stop("At least one model feature has zero or invalid training variance.", call. = FALSE)
}

train_model <- standardize_features(train_data, feature_center, feature_scale)
test_model <- standardize_features(test_data, feature_center, feature_scale)

logit_fit <- glm(
  next_month_up ~ available_unemployment + available_unemp_change +
    monthly_return + annualized_volatility,
  data = train_model,
  family = binomial()
)

model_probability <- predict(logit_fit, newdata = test_model, type = "response")
baseline_probability_value <- mean(train_data$next_month_up)
baseline_probability <- rep(baseline_probability_value, nrow(test_data))

evaluation_metrics <- bind_rows(
  classification_metrics(
    test_data$next_month_up,
    model_probability,
    "Logistic regression"
  ),
  classification_metrics(
    test_data$next_month_up,
    baseline_probability,
    "Historical up-rate baseline"
  )
)

metric_value <- function(model_name, metric_name) {
  evaluation_metrics %>%
    filter(model == model_name, metric == metric_name) %>%
    pull(value)
}

test_results <- test_data %>%
  transmute(
    month_date,
    actual = next_month_up,
    actual_label = if_else(next_month_up == 1, "Up month", "Down month"),
    predicted_probability = model_probability,
    predicted = as.integer(model_probability >= 0.5)
  )

confusion_matrix <- test_results %>%
  transmute(
    Actual = factor(actual_label, levels = c("Down month", "Up month")),
    Predicted = factor(
      if_else(predicted == 1, "Up month", "Down month"),
      levels = c("Down month", "Up month")
    )
  ) %>%
  count(Actual, Predicted, name = "n") %>%
  complete(Actual, Predicted, fill = list(n = 0))

coefficient_matrix <- coef(summary(logit_fit))

coefficient_table <- as.data.frame(coefficient_matrix) %>%
  rownames_to_column("term") %>%
  as_tibble() %>%
  filter(term != "(Intercept)") %>%
  transmute(
    term,
    term_label = recode(
      term,
      available_unemployment = "Latest unemployment rate",
      available_unemp_change = "Latest unemployment change",
      monthly_return = "Current monthly return",
      annualized_volatility = "Current annualized volatility"
    ),
    estimate = Estimate,
    standard_error = `Std. Error`,
    odds_ratio = exp(estimate),
    conf_low = exp(estimate - 1.96 * standard_error),
    conf_high = exp(estimate + 1.96 * standard_error),
    p_value = `Pr(>|z|)`
  )

regime_cutoff <- median(descriptive_data$unemployment_rate, na.rm = TRUE)

regime_summary <- descriptive_data %>%
  mutate(
    unemp_regime = if_else(
      unemployment_rate > regime_cutoff,
      "Higher unemployment",
      "Lower unemployment"
    )
  ) %>%
  group_by(unemp_regime) %>%
  summarise(
    months = n(),
    avg_return = mean(monthly_return),
    avg_volatility = mean(annualized_volatility),
    .groups = "drop"
  )

coverage_table <- tribble(
  ~Series, ~Start, ~End, ~Observations,
  "S&P 500 daily prices",
  format(min(sp500_raw$date), "%Y-%m-%d"),
  format(max(sp500_raw$date), "%Y-%m-%d"),
  nrow(sp500_raw),
  "U.S. unemployment rate",
  format(min(unemp_monthly$date), "%Y-%m"),
  format(max(unemp_monthly$date), "%Y-%m"),
  nrow(unemp_monthly),
  "Release-aware model sample",
  format(min(model_data$month_date), "%Y-%m"),
  format(max(model_data$month_date), "%Y-%m"),
  nrow(model_data)
)

model_accuracy_value <- metric_value("Logistic regression", "Accuracy")
baseline_accuracy_value <- metric_value("Historical up-rate baseline", "Accuracy")
model_auc_value <- metric_value("Logistic regression", "ROC AUC")

performance_summary <- if (
  model_accuracy_value > baseline_accuracy_value && model_auc_value > 0.5
) {
  sprintf(
    "The model exceeded the historical up-rate baseline by %s, with an ROC AUC of %.2f.",
    percent(model_accuracy_value - baseline_accuracy_value, accuracy = 0.1),
    model_auc_value
  )
} else {
  sprintf(
    "The model did not improve on the historical up-rate baseline; its ROC AUC was %.2f.",
    model_auc_value
  )
}
