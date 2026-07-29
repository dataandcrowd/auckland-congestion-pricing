library(sf)
library(dplyr)
library(sfnetworks)
library(tidygraph)
library(mapview)

# 0) Read data and align CRS -------------------------------------------------
# If your TomTom roads are not already in 2193, transform them.
sa3        <- st_read("sa3_akl.gpkg", quiet = TRUE)
rd         <- read_sf("AT Data//tomtom_major_roads.gpkg") 
avoid_poly <- st_read("akl_cbd.gpkg", quiet = TRUE) |> st_make_valid()

# 1) Build the network -------------------------------------------------------
net <- as_sfnetwork(rd, directed = FALSE)

# 2) Define origin and destination points (NZTM) -----------------------------
from_pt <- st_sfc(st_point(c(1759726.065, 5917795.807)), crs = 2193)
to_pt   <- st_sfc(st_point(c(1755797.914, 5920892.114)), crs = 2193)

# 3) Tag edges intersecting the avoid polygon + create weights ---------------
net1 <- net |>
  activate(edges) |>
  mutate(
    in_avoid = lengths(st_intersects(geom, st_union(avoid_poly))) > 0,
    w_base   = as.numeric(st_length(geom)),
    w_penal  = if_else(in_avoid, w_base * 50, w_base)
  )

# 4) Route: baseline (distance) and penalised -------------------------------
sp_base <- st_network_paths(
  net1,
  from = from_pt,
  to   = to_pt,
  weights = "w_base"
)

sp_pen  <- st_network_paths(
  net1,
  from = from_pt,
  to   = to_pt,
  weights = "w_penal"
)

# 5) Convert edge paths to sf objects ----------------------------------------
edge_ids_base <- unlist(sp_base$edge_paths)
edge_ids_pen  <- unlist(sp_pen$edge_paths)

route_base_sf <- net1 |>
  activate(edges) |>
  slice(edge_ids_base) |>
  st_as_sf() |>
  st_union() |>
  st_line_merge() |>
  st_as_sf() |>
  mutate(scenario = "base")

route_pen_sf <- net1 |>
  activate(edges) |>
  slice(edge_ids_pen) |>
  st_as_sf() |>
  st_union() |>
  st_line_merge() |>
  st_as_sf() |>
  mutate(scenario = "penalised")

# 6) Compare lengths ----------------------------------------------------------
len_base_m <- st_length(route_base_sf) |> as.numeric()
len_pen_m  <- st_length(route_pen_sf)  |> as.numeric()

tibble::tibble(
  scenario   = c("base", "penalised"),
  length_m   = c(len_base_m, len_pen_m),
  pct_change = c(NA_real_, 100 * (len_pen_m / len_base_m - 1))
)
# > This shows how much longer the penalised route is.

# 7) Quick visual check -------------------------------------------------------
library(mapview)

# pick distinct colours for clarity
mv_base <- mapview(route_base_sf,  layer.name = "Base",       color = "blue",  lwd = 5, legend = FALSE)
mv_pen  <- mapview(route_pen_sf,   layer.name = "Penalised",  color = "orange", lwd = 6, legend = FALSE)
# mv_cbd  <- mapview(st_as_sf(net1, "edges") |>
#                      dplyr::filter(in_avoid),
#                    layer.name = "Avoid edges",
#                    color = "red", lwd = 2, legend = FALSE)

# if you also want to show the polygon area (transparent fill)
mv_poly <- mapview(avoid_poly, layer.name = "Avoid area",
                   col.regions = "red", alpha.regions = 0.15, legend = FALSE)

mv_base + mv_pen +  mv_poly





