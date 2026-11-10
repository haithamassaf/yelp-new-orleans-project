library(tidyverse)
library(sf)
library(tigris)
library(viridis)

options(tigris_use_cache = TRUE)
suppressMessages(sf_use_s2(FALSE))
dir.create("figures", showWarnings = FALSE)

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")
category_reviews <- readRDS("data/new_orleans/selected_reviews.rds")

new_orleans_boundary <- places(state = "LA", cb = TRUE, year = 2024, progress_bar = FALSE) |>
  filter(NAME == "New Orleans") |>
  st_transform(4326)

restaurant_points <- selected_restaurants |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |>
  st_filter(new_orleans_boundary, .predicate = st_within)

nola_url <- "https://maps.nola.gov/server/rest/services"
query <- "query?where=1%3D1&outFields=*&outSR=4326&f=geojson"

zcta_boundaries <- zctas(cb = FALSE, year = 2020, starts_with = c("700", "701"), progress_bar = FALSE) |>
  st_transform(4326) |>
  st_filter(new_orleans_boundary, .predicate = st_intersects) |>
  transmute(area_name = ZCTA5CE20)

zcta_projected <- st_transform(zcta_boundaries, 26915)
overlap <- as.numeric(st_area(st_intersection(zcta_projected, st_transform(st_geometry(new_orleans_boundary), 26915)))) /
  as.numeric(st_area(zcta_projected))
zcta_boundaries <- zcta_boundaries[overlap > 0.25, ]

tract_boundaries <- tracts(state = "LA", county = "Orleans", cb = TRUE, year = 2024, progress_bar = FALSE) |>
  st_transform(4326) |>
  transmute(area_name = NAMELSAD)

nsa_boundaries <- st_read(file.path(nola_url, "Reference/Reference_Layers/MapServer/0", query), quiet = TRUE) |>
  transmute(area_name = str_to_title(GNOCDC_LAB))

ward_boundaries <- st_read(file.path(nola_url, "Administrative/Administrative_Layers/MapServer/3", query), quiet = TRUE) |>
  transmute(area_name = paste("Ward", WARD))

geographies <- list(
  "ZIP/ZCTA" = zcta_boundaries,
  "Census tract" = tract_boundaries,
  "Neighborhood Statistical Area" = nsa_boundaries,
  "Ward" = ward_boundaries
)

reviewer_baselines <- category_reviews |>
  group_by(user_id) |>
  summarise(reviewer_mean = mean(stars), reviewer_review_count = n(), .groups = "drop")

eligible_reviews <- category_reviews |>
  inner_join(reviewer_baselines, by = "user_id") |>
  filter(reviewer_review_count >= 5) |>
  mutate(normalized_score = stars - reviewer_mean)

assign_areas <- function(boundaries) {
  restaurant_points |>
    st_join(boundaries, join = st_within, left = TRUE) |>
    st_drop_geometry() |>
    distinct(business_id, .keep_all = TRUE)
}

summarise_areas <- function(assigned) {
  normalized_by_area <- eligible_reviews |>
    inner_join(select(assigned, business_id, area_name), by = "business_id") |>
    group_by(area_name) |>
    summarise(
      eligible_reviews = n(),
      average_normalized_score = mean(normalized_score),
      .groups = "drop"
    )

  assigned |>
    filter(!is.na(area_name)) |>
    group_by(area_name) |>
    summarise(
      number_of_restaurants = n(),
      average_business_stars = mean(stars),
      median_business_stars = median(stars),
      total_reviews = sum(review_count),
      .groups = "drop"
    ) |>
    left_join(normalized_by_area, by = "area_name") |>
    arrange(desc(number_of_restaurants))
}

assigned_by_system <- map(geographies, assign_areas)
summary_by_system <- map(assigned_by_system, summarise_areas)

comparison_table <- imap_dfr(summary_by_system, function(area_summary, system) {
  tibble(
    geographic_system = system,
    number_of_areas = nrow(geographies[[system]]),
    areas_with_restaurants = nrow(area_summary),
    areas_with_10_or_more = sum(area_summary$number_of_restaurants >= 10),
    areas_with_under_5 = sum(area_summary$number_of_restaurants < 5),
    restaurants_assigned = sum(!is.na(assigned_by_system[[system]]$area_name)),
    unmatched_restaurants = sum(is.na(assigned_by_system[[system]]$area_name)),
    smallest_area_count = min(area_summary$number_of_restaurants),
    largest_area_count = max(area_summary$number_of_restaurants),
    median_area_count = median(area_summary$number_of_restaurants)
  )
})

print(comparison_table, width = Inf)

iwalk(summary_by_system, function(area_summary, system) {
  cat("\n", system, "\n")
  area_summary |>
    filter(number_of_restaurants >= 10) |>
    arrange(desc(average_normalized_score)) |>
    mutate(across(where(is.double), \(x) round(x, 2))) |>
    print(n = 15, width = Inf)
})

map_system <- function(system, file_name) {
  map_data <- geographies[[system]] |>
    left_join(summary_by_system[[system]], by = "area_name") |>
    mutate(number_of_restaurants = replace_na(number_of_restaurants, 0L)) |>
    st_intersection(st_geometry(new_orleans_boundary))

  area_map <- ggplot() +
    geom_sf(data = map_data, aes(fill = number_of_restaurants), color = "white", linewidth = 0.2) +
    geom_sf(data = restaurant_points, color = "black", size = 0.5, alpha = 0.5) +
    scale_fill_viridis_c(option = "D", trans = "sqrt", name = "Restaurants") +
    coord_sf(xlim = c(-90.14, -89.92), ylim = c(29.89, 30.07)) +
    labs(
      title = paste("Seafood and Cajun/Creole Restaurants by", system),
      subtitle = paste(nrow(geographies[[system]]), "areas; black dots are restaurants")
    ) +
    theme_void() +
    theme(plot.background = element_rect(fill = "white", color = NA))

  ggsave(file.path("figures", file_name), area_map, width = 8, height = 7, dpi = 150, bg = "white")
}

map_system("ZIP/ZCTA", "map_zcta.png")
map_system("Census tract", "map_tract.png")
map_system("Neighborhood Statistical Area", "map_neighborhood.png")
map_system("Ward", "map_ward.png")

size_plot <- imap_dfr(summary_by_system, \(area_summary, system) mutate(area_summary, geographic_system = system)) |>
  mutate(geographic_system = fct_reorder(geographic_system, number_of_restaurants, median)) |>
  ggplot(aes(x = number_of_restaurants, y = geographic_system)) +
  geom_vline(xintercept = 10, linetype = "dashed", color = "grey50") +
  geom_jitter(height = 0.15, width = 0, alpha = 0.6, color = "#2c7fb8") +
  geom_boxplot(fill = NA, outlier.shape = NA, width = 0.5) +
  scale_x_log10() +
  labs(
    title = "How Many Restaurants Fall in Each Area?",
    subtitle = "Each dot is one area that has at least one restaurant; dashed line marks 10 restaurants",
    x = "Restaurants per area (log scale)",
    y = NULL
  ) +
  theme_minimal()

ggsave("figures/area_size_comparison.png", size_plot, width = 9, height = 5, dpi = 150, bg = "white")

neighborhood_rank_plot <- summary_by_system[["Neighborhood Statistical Area"]] |>
  filter(number_of_restaurants >= 10) |>
  mutate(area_name = fct_reorder(area_name, average_normalized_score)) |>
  ggplot(aes(x = average_normalized_score, y = area_name)) +
  geom_vline(xintercept = 0, color = "grey60") +
  geom_point(aes(size = number_of_restaurants, color = average_business_stars)) +
  scale_color_viridis_c(option = "C", name = "Avg business\nstars") +
  scale_size_continuous(name = "Restaurants") +
  labs(
    title = "Neighborhoods with 10+ Seafood and Cajun/Creole Restaurants",
    subtitle = "Normalized score = stars minus the reviewer's usual rating (reviewers with 5+ reviews)",
    x = "Average reviewer-adjusted score",
    y = NULL
  ) +
  theme_minimal()

ggsave("figures/neighborhood_ranking.png", neighborhood_rank_plot, width = 9, height = 6, dpi = 150, bg = "white")

saveRDS(assigned_by_system[["Neighborhood Statistical Area"]], "data/new_orleans/selected_restaurants_neighborhoods.rds", compress = "xz")
