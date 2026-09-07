# Deterministic observations constructed from clock positions and integer rules.
# No source dataset, patient record, or learned distribution is used.
make_synthetic_observations <- function() {
  grid <- expand.grid(hour = 0:23, day = 1:14, patient = 1:6, KEEP.OUT.ATTRS = FALSE)
  grid <- grid[(seq_len(nrow(grid)) %% 31L) != 0L, , drop = FALSE]
  p <- grid$patient; h <- grid$hour; d <- grid$day
  asleep <- h < 6L | h >= 22L
  asleep[h == 5L & (p + d) %% 3L == 0L] <- FALSE
  asleep[h %in% c(13L, 14L) & p %in% c(2L, 5L) & d > 7L] <- TRUE
  asleep[h == 15L & (p + d) %% 4L == 0L] <- TRUE
  behaviour <- !asleep & ((h >= 16L & h <= 19L & (p + d) %% 3L == 0L) | (h + p + d) %% 17L == 0L)
  behaviour[p == 3L & d > 7L] <- FALSE
  stamp <- sprintf("2026-08-%02dT%02d:00:00-0400", d, h)
  out <- data.frame(observation_id = sprintf("SYN-%d-%02d-%02d", p, d, h),
                    patient_id = sprintf("Demo participant %02d", p),
                    episode_id = sprintf("DEMO-EP-%02d", p),
                    unit = ifelse(p <= 3L, "Demo Unit A", "Demo Unit B"),
                    observed_at = stamp, sleep_state = ifelse(asleep, "Asleep", "Awake"),
                    behaviour = ifelse(behaviour, "YES", "NO"), awake_calm = "", sleeping = "",
                    stringsAsFactors = FALSE)
  fallback <- seq_len(nrow(out)) %% 13L == 0L
  out$awake_calm[fallback & !asleep] <- "Awake/Calm"
  out$sleeping[fallback & asleep] <- "Sleeping"
  out$sleep_state[fallback] <- ""
  unknown <- seq_len(nrow(out)) %% 29L == 0L
  out$sleep_state[unknown] <- ""; out$awake_calm[unknown] <- ""; out$sleeping[unknown] <- ""
  out$behaviour[seq_len(nrow(out)) %% 23L == 0L] <- ""
  out
}
