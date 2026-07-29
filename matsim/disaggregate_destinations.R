# ============================================================================
# Disaggregate work/education destinations in the MATSim plans file
# ----------------------------------------------------------------------------
# WHY:
#   plans_2023.xml places every "home" at a fine, dispersed location (319,192
#   distinct points) but snaps every "work" / "education" activity to its SA2
#   centroid (only 589 / 487 distinct points; 460 of them shared between the
#   two layers -> proof they come from a common zone-centroid lookup).
#
#   For a congestion-pricing simulation that is the problem: all commuters into
#   a zone arrive at ONE identical point, which artificially concentrates
#   congestion on ~589 nodes, biases which agents fall inside a priced cordon,
#   and zeroes-out intra-zone trips.
#
# WHAT THIS DOES:
#   1. Reads the SA2 2023 polygons (NZTM / EPSG:2193).
#   2. Finds every distinct destination centroid in the plans file and assigns
#      it to the SA2 polygon that contains it.
#   3. Replaces each work/education activity's centroid with a fresh random
#      point drawn INSIDE that SA2 (uniform by default; optionally weighted by
#      a land-use / network layer so points land on plausible ground).
#   4. Stream-rewrites the plans XML to a new file. Homes are left untouched.
#
# OUTPUT:  plans_2023_disaggregated.xml  (ready to re-run to equilibrium)
#
# NOTE ON DATA:  the repo only ships SA3 boundaries (sa3_akl.gpkg). You must
#   supply the Stats NZ SA2 2023 layer. Download "Statistical Area 2 2023
#   (generalised)" from https://datafinder.stats.govt.nz and clip to Auckland,
#   or reuse the same source that produced the centroids in the plans file.
# ============================================================================

library(sf)
library(tidyverse)

set.seed(2023)  # reproducible jitter

# ---- 0) Config -------------------------------------------------------------
PLANS_IN   <- "../plans_2023.xml"
PLANS_OUT  <- "../plans_2023_disaggregated.xml"
SA2_FILE   <- "sa2_akl.gpkg"          # <-- you provide this (SA2 2023, EPSG:2193)
SA2_CODE   <- "SA22023_V1_00"         # SA2 code field; adjust if named differently
CRS_NZTM   <- 2193
DEST_TYPES <- c("work", "education")  # activity types to disaggregate

# Optional land-use / road mask so jittered points avoid water & parks.
# Set to NULL for plain uniform-in-polygon sampling.
LANDUSE_MASK <- NULL                  # e.g. st_read("akl_builtup.gpkg")

stopifnot(file.exists(PLANS_IN))
if (!file.exists(SA2_FILE))
  stop("SA2 layer not found: ", SA2_FILE,
       "\nDownload Statistical Area 2 2023 from datafinder.stats.govt.nz, ",
       "clip to Auckland, save as '", SA2_FILE, "'.")

# ---- 1) Load SA2 polygons --------------------------------------------------
sa2 <- st_read(SA2_FILE, quiet = TRUE) |>
  st_transform(CRS_NZTM) |>
  st_make_valid()
if (!SA2_CODE %in% names(sa2))
  stop("SA2 code field '", SA2_CODE, "' not in layer. Fields: ",
       paste(setdiff(names(sa2), attr(sa2, "sf_column")), collapse = ", "))
sa2$sa2 <- as.character(sa2[[SA2_CODE]])
sa2 <- sa2 |> select(sa2)                  # select() on sf keeps the geometry

if (!is.null(LANDUSE_MASK)) {
  mask <- st_union(st_transform(st_make_valid(LANDUSE_MASK), CRS_NZTM))
  sa2  <- st_intersection(sa2, mask)
  sa2  <- sa2[!st_is_empty(sa2), ]
}

# ---- 2) Pull distinct destination centroids + occurrence counts ------------
# Fast path: let grep find the destination lines instead of parsing 425 MB.
dest_lines <- system2("grep", c("-hoE",
  shQuote(sprintf('type="(%s)" x="[0-9.]+" y="[0-9.]+"',
                  paste(DEST_TYPES, collapse = "|"))), shQuote(PLANS_IN)),
  stdout = TRUE)

# Keep x/y as the VERBATIM strings from the file: they become the lookup key
# during the rewrite, so they must match the file byte-for-byte (converting to
# double would round 17-digit coords to ~15 and break the join).
dest <- tibble(raw = dest_lines) |>
  extract(raw, c("type", "x", "y"),
          'type="([a-z]+)" x="([0-9.]+)" y="([0-9.]+)"', convert = FALSE) |>
  count(type, x, y, name = "n_occ")              # one row per distinct centroid

message(sprintf("Distinct destination centroids: %d (%d activities)",
                nrow(dest), sum(dest$n_occ)))

# ---- 3) Assign each centroid to its containing SA2 -------------------------
# Build geometry from numeric copies but KEEP the verbatim x/y strings.
cent_sf <- dest |>
  mutate(.X = as.numeric(x), .Y = as.numeric(y)) |>
  st_as_sf(coords = c(".X", ".Y"), crs = CRS_NZTM, remove = TRUE)
cent_sf <- st_join(cent_sf, sa2, join = st_within)

# centroids that miss a polygon (edge/rounding) -> snap to nearest SA2
miss <- is.na(cent_sf$sa2)
if (any(miss)) {
  nn <- st_nearest_feature(cent_sf[miss, ], sa2)
  cent_sf$sa2[miss] <- sa2$sa2[nn]
  message(sprintf("  %d centroids fell outside any SA2 -> snapped to nearest",
                  sum(miss)))
}

# ---- 4) Pre-sample a jitter pool per centroid (sized to its occurrences) ----
# Each work/education activity will consume one fresh point from its zone, so
# no two agents share a destination coordinate any more.
zones <- sa2[sa2$sa2 %in% cent_sf$sa2, ]

sample_pool <- function(code, k) {
  poly <- st_geometry(zones[zones$sa2 == code, ])
  pts  <- st_sample(poly, size = k, type = "random", exact = TRUE)
  # st_sample can under-deliver on odd geometries; top up if needed
  while (length(pts) < k)
    pts <- c(pts, st_sample(poly, size = k - length(pts), type = "random"))
  st_coordinates(pts[seq_len(k)])
}

cent_sf <- cent_sf |>
  mutate(key = paste(x, y))                       # original coord as lookup key

# Build, per original coordinate key, a matrix of replacement points and a
# consumption counter (mutable env = fast during the stream rewrite).
pool_env  <- new.env(parent = emptyenv())   # key -> matrix of [X,Y]
count_env <- new.env(parent = emptyenv())   # key -> integer cursor
for (i in seq_len(nrow(cent_sf))) {
  k <- cent_sf$key[i]
  assign(k, sample_pool(cent_sf$sa2[i], cent_sf$n_occ[i]), envir = pool_env)
  assign(k, 0L, envir = count_env)
}
message("Jitter pools built.")

# ---- 5) Stream-rewrite the plans XML ---------------------------------------
# The file is one element per line, so we can rewrite line-by-line in chunks
# without holding 425 MB in memory. Only work/education lines are touched.
con_in  <- file(PLANS_IN,  "r")
con_out <- file(PLANS_OUT, "w")
on.exit({ close(con_in); close(con_out) }, add = TRUE)

dest_re <- sprintf('<activity type="(%s)"', paste(DEST_TYPES, collapse = "|"))
CHUNK   <- 200000L
n_rewritten <- 0L

repeat {
  lines <- readLines(con_in, n = CHUNK, warn = FALSE)
  if (length(lines) == 0) break

  hit <- grep(dest_re, lines)
  for (j in hit) {
    m <- regmatches(lines[j],
           regexec('x="([0-9.]+)" y="([0-9.]+)"', lines[j]))[[1]]
    key <- paste(m[2], m[3])
    idx <- get(key, envir = count_env) + 1L
    assign(key, idx, envir = count_env)
    xy  <- get(key, envir = pool_env)[idx, ]
    lines[j] <- sub('x="[0-9.]+" y="[0-9.]+"',
                    sprintf('x="%.6f" y="%.6f"', xy[1], xy[2]), lines[j])
    n_rewritten <- n_rewritten + 1L
  }
  writeLines(lines, con_out)
}
message(sprintf("Rewrote %d destination activities -> %s",
                n_rewritten, PLANS_OUT))

# ---- 6) Sanity check -------------------------------------------------------
# Distinct work points should now be ~ the number of work activities, not 589.
check <- system2("grep", c("-hoE",
  shQuote('type="work" x="[0-9.]+" y="[0-9.]+"'), shQuote(PLANS_OUT)),
  stdout = TRUE)
message(sprintf("Distinct work points after disaggregation: %d (was 589)",
                length(unique(check))))
