library(sf)
library(tidyverse)


# your uploaded file
od_raw <- read_csv("OD_by_SA3.csv")


od <- od_raw |>
  transmute(
    o = SA32023_V1_00_NAME_ASCII_usual_residence_address,
    d = SA32023_V1_00_NAME_ASCII_workplace_address,
    # clean suppressed values, form a composite
    car_private = na_if(`2023_Drive_a_private_car_truck_or_van`, -999),
    car_company = na_if(`2023_Drive_a_company_car_truck_or_van`, -999),
    car_pass    = na_if(`2023_Passenger_in_a_car_truck_van_or_company_bus`, -999),
    flow = coalesce(car_private, 0) + coalesce(car_company, 0) + coalesce(car_pass, 0)
  ) |>
  filter(!is.na(o), !is.na(d)) |>
  mutate(o = as.character(o), d = as.character(d)) |>
  filter(o != d) |>                     # drop within-zone for lines
  group_by(o, d) |>                     # just in case there are duplicates
  summarise(flow = sum(flow), .groups = "drop") |>
  filter(flow > 0)


od

# 2) read SA3 polygons and get centroids
# Use your local SA3 2023 layer; replace field names if different.
# Typical Stats NZ SA3 code field: "SA32023_V1_00"
sa3 <- st_read("sa3_akl.gpkg")

cent <- sa3 |>
  select(SA3_code = SA32025_V1_00_NAME_ASCII) |>
  st_centroid() |>
  rename(centroid = geom)

# 3) attach origin and destination centroids
od_pts <- od |>
  left_join(cent, by = c("o" = "SA3_code")) |>
  rename(geom_o = centroid) |>
  left_join(cent, by = c("d" = "SA3_code")) |>
  rename(geom_d = centroid)

# sanity checks for mismatched SA3s
missing_o <- od_pts |> filter(is.na(geom_o)) |> distinct(o)
missing_d <- od_pts |> filter(is.na(geom_d)) |> distinct(d)
print(list(missing_origins = missing_o, missing_destinations = missing_d))

od_pts_ok <- od_pts |>
  filter(!st_is_empty(geom_o), !st_is_empty(geom_d)) |>
  filter(!is.na(geom_o), !is.na(geom_d))

# quick check
nrow(od_pts); nrow(od_pts_ok)

# 1) build lines from two-point coordinates
make_line <- function(p1, p2) {
  coords <- rbind(st_coordinates(p1), st_coordinates(p2))
  st_linestring(coords)
}

geoms <- st_sfc(
  map2(od_pts_ok$geom_o, od_pts_ok$geom_d, make_line),
  crs = st_crs(sa3)
)

od_lines <- st_sf(geometry = geoms) |>
  bind_cols(od_pts_ok |> st_drop_geometry())

# 2) thin to top flows
top_n <- 500
od_top <- od_lines |> arrange(desc(flow)) |> slice_head(n = top_n)

# 6) map
ggplot() +
  geom_sf(data = sa3, fill = "grey95", colour = "white", linewidth = 0.2) +
  geom_sf(data = od_top, aes(linewidth = flow, alpha = flow), colour = "steelblue") +
  scale_linewidth(range = c(0.15, 2.2)) +
  scale_alpha(range = c(0.25, 0.9)) +
  labs(
    title = "Top inter-SA3 travel-to-work desire lines",
    subtitle = "Composite car trips = private + company + passenger",
    linewidth = "Flow",
    alpha = "Flow"
  ) +
  theme_minimal()

#ggsave("SA3_OD_Map.png")


# Web map
library(mapview)
mapview(od_top, zcol = "flow", lwd = "flow", legend = TRUE) +
  mapview(sa3, alpha.regions = 0.1, col.regions = "grey")

library(tmap)
tmap_mode("view")  # interactive but with tmap styling

tm_shape(sa3) + tm_polygons(col = "grey95") +
  tm_shape(od_top) +
  tm_lines(lwd = "flow", scale = 5, col = "flow", palette = "Blues", alpha = 0.9) +
  tm_view(basemaps = c("CartoDB.Positron","OpenStreetMap"))


##############
library(scales)
od_named <- od |> mutate(o_name = o, d_name = d)  # fallback to codes

# Order rows and columns by marginal totals so the heatmap structure is readable
o_tot <- od_named |> group_by(o_name) |> summarise(outflow = sum(flow), .groups = "drop") |> arrange(desc(outflow))
d_tot <- od_named |> group_by(d_name) |> summarise(inflow  = sum(flow), .groups = "drop") |> arrange(desc(inflow))

od_hm <- od_named |>
  mutate(
    o_name = factor(o_name, levels = o_tot$o_name),
    d_name = factor(d_name, levels = d_tot$d_name)
  )

# Optional: focus on top K origins and destinations if you have many SA3s
K <- 40  # tune for your figure
o_keep <- head(o_tot$o_name, K)
d_keep <- head(d_tot$d_name, K)
od_hm_top <- od_hm |> filter(o_name %in% o_keep, d_name %in% d_keep)

# Absolute flow heatmap
p_abs <- ggplot(od_hm_top, aes(x = d_name, y = o_name, fill = flow)) +
  geom_tile() +
  scale_fill_viridis_c(labels = label_number(big.mark = ","), trans = "sqrt") +
  labs(
    title = "Origin–destination heatmap (top 50 absolute flows)",
    x = "Destination SA3",
    y = "Origin SA3",
    fill = "Trips"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1),
    panel.grid = element_blank()
  )

p_abs

ggsave("SA3_OD_HeatMap.png", height = 6, width = 7)


# Row-normalised shares (each origin sums to 1)
od_share <- od_hm |>
  group_by(o_name) |>
  mutate(share = flow / sum(flow)) |>
  ungroup()

od_share_top <- od_share |> filter(o_name %in% o_keep, d_name %in% d_keep)

p_share <- ggplot(od_share_top, aes(x = d_name, y = o_name, fill = share)) +
  geom_tile() +
  scale_fill_viridis_c(labels = percent_format(accuracy = 1)) +
  labs(
    title = "Origin–destination heatmap (top 50 row-normalised shares)",
    x = "Destination SA3",
    y = "Origin SA3",
    fill = "Share"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1),
    panel.grid = element_blank()
  )

p_share

ggsave("SA3_OD_HeatMap_normalised.png", height = 6, width = 7)




