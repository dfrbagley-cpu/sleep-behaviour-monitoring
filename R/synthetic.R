# Reproducible fictional observations: no patient records or learned distributions.
# Save and restore caller RNG state so demo generation cannot alter other analyses.
make_synthetic_observations <- function() {
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  old_kind <- RNGkind()
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection"); set.seed(260907L)
  grid <- expand.grid(hour = 0:23, day = 1:56, patient = 1:8, KEEP.OUT.ATTRS = FALSE)
  p <- grid$patient; h <- grid$hour; d <- grid$day; n <- nrow(grid)
  day_index <- (p - 1L) * 56L + d
  day_jitter <- rnorm(8L * 56L, sd = .06)[day_index]
  sleep_prob <- ifelse(h < 6L | h >= 22L, .92, ifelse(h %in% 12:14, .12, .03))
  sleep_prob <- pmax(.01, pmin(.99, sleep_prob + day_jitter + ifelse(p == 2L & d > 28L & h %in% 12:15, .45, 0)))
  asleep <- runif(n) < sleep_prob
  type_names <- c("verbal_responses", "physical_responses", "repetitive_vocalizations", "restlessness", "repeated_requests",
                  "intrusiveness", "sexual_behaviours", "exit_seeking", "resistance_to_care")
  probabilities <- c(.09, .035, .05, .13, .08, .035, .015, .04, .06)
  flags <- lapply(seq_along(type_names), function(i) {
    prob <- probabilities[i] + (p %% 3L) * .015 + pmax(day_jitter, -.02)
    prob <- prob + ifelse(h %in% 16:19, .04, 0)
    if (i == 4L) prob <- prob + ifelse(p == 2L & d > 28L, .3, 0)
    if (i == 1L) prob <- prob - ifelse(p == 3L & d > 28L, .08, 0)
    !asleep & runif(n) < pmax(.002, pmin(.85, prob))
  })
  any_behaviour <- Reduce(`|`, flags)
  dates <- as.Date("2026-07-01") + d - 1L
  out <- data.frame(observation_id = sprintf("SYN-%d-%02d-%02d", p, d, h),
    patient_id = sprintf("Demo participant %02d", p), episode_id = sprintf("DEMO-EP-%02d", p),
    unit = ifelse(p <= 4L, "Demo Unit A", "Demo Unit B"),
    observed_at = paste0(format(dates, "%Y-%m-%d"), sprintf("T%02d:00:00-0400", h)),
    sleep_state = ifelse(asleep, "Asleep", "Awake"), behaviour = ifelse(any_behaviour, "YES", "NO"),
    awake_calm = "", sleeping = "", stringsAsFactors = FALSE)
  for (i in seq_along(type_names)) {
    out[[type_names[i]]] <- ifelse(flags[[i]], "YES", "NO")
    out[[type_names[i]]][(seq_len(n) + i * 7L) %% 79L == 0L] <- ""
  }
  fallback <- seq_len(n) %% 13L == 0L
  out$awake_calm[fallback & !asleep] <- "Awake/Calm"
  out$sleeping[fallback & asleep] <- "Sleeping"; out$sleep_state[fallback] <- ""
  unknown <- seq_len(n) %% 101L == 0L
  out$sleep_state[unknown] <- ""; out$awake_calm[unknown] <- ""; out$sleeping[unknown] <- ""
  out$behaviour[seq_len(n) %% 97L == 0L] <- ""
  out
}
