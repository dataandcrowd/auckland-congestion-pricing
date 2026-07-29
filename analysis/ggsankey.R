library(ggsankeyfier)
library(tidyverse)
library(sf)


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


# Get list of Auckland SA3 names from your shapefile
sa3 <- st_read("sa3_akl.gpkg")

akl_names <- sa3 %>%
  pull(SA32025_V1_00_NAME_ASCII) %>%
  unique()



# Keep only OD flows where both origin and destination are in Auckland
od_akl <- od %>%
  filter(o %in% akl_names & d %in% akl_names)


# Keep the top L flows for readability
L <- 30
od_top <- od_akl |> arrange(desc(flow)) |> slice_head(n = L)

# Wrap long labels if needed
wrap_lab <- function(x, width = 20) str_wrap(x, width = width)

# 2) Pivot to ggsankeyfier "pivot1" format
od_pivot1 <- od_top |>
  mutate(edge_id = row_number()) |>
  transmute(edge_id, RCSES = flow,
            o_name = wrap_lab(o), d_name = wrap_lab(d)) |>
  pivot_longer(c(o_name, d_name), names_to = "connector", values_to = "node") |>
  mutate(
    stage = if_else(connector == "o_name", "origin", "destination"),
    connector = if_else(connector == "o_name", "from", "to"),
    node = factor(node),
    stage = factor(stage, levels = c("origin","destination"))
  )

# 3) Compute node block mid-points for labels (per stage)
node_labels <- od_pivot1 |>
  group_by(stage, node) |>
  summarise(height = sum(RCSES), .groups = "drop") |>
  arrange(stage, desc(height)) |>
  group_by(stage) |>
  mutate(
    ymax = cumsum(height),
    ymin = ymax - height,
    y    = (ymin + ymax) / 2,
    hjust = if_else(stage == "origin", 1, 0),
    x      = as.numeric(stage) + if_else(stage == "origin", -0.04, 0.04)
  )

# Optional: drop tiny nodes to avoid clutter (eg < 1% of the stage total)
node_labels <- node_labels |>
  group_by(stage) |>
  mutate(stage_total = sum(height)) |>
  ungroup() |>
  filter(height / stage_total >= 0.01)

# 4) Plot with labels outside the blocks

ggplot(od_pivot1,
       aes(x = stage, y = RCSES, group = node,
           connector = connector, edge_id = edge_id)) +
  geom_sankeyedge(v_space = 0, fill = "steelblue", alpha = 0.55) +
  geom_sankeynode(v_space = 0, fill = "grey92", colour = "black") +
  geom_text(data = node_labels,
            aes(x = x, y = y, label = node, hjust = hjust),
            inherit.aes = FALSE, size = 3) +
  # If overlap persists, swap the previous layer for:
  # ggrepel::geom_text_repel(data = node_labels,
  #   aes(x = x, y = y, label = node, hjust = hjust),
  #   inherit.aes = FALSE, size = 3, direction = "y", min.segment.length = 0) +
  labs(
    title = "SA3 origin to destination flows",
    subtitle = paste0("Top ", L, " links by trips"),
    x = NULL, y = "Trips"
  ) +
  theme_minimal(base_size = 12) +
  theme(panel.grid = element_blank())
