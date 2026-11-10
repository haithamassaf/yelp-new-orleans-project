library(tidyverse)
library(sf)
library(tigris)

options(tigris_use_cache = TRUE)
dir.create("figures", showWarnings = FALSE)

la_restaurants <- readRDS("data/new_orleans/business_la_restaurants.rds")
selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")

louisiana_places <- places(state = "LA", cb = TRUE, year = 2024, class = "sf", progress_bar = FALSE) |>
  st_transform(4326)

new_orleans_boundary <- louisiana_places |>
  filter(NAME == "New Orleans")

restaurant_points <- la_restaurants |>
  filter(!is.na(longitude), !is.na(latitude)) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

restaurants_with_place <- restaurant_points |>
  st_join(louisiana_places |> select(GEOID, place_name = NAME), join = st_within, left = TRUE) |>
  mutate(place_name = replace_na(place_name, "Outside any Census place"))

restaurants_with_place |>
  st_drop_geometry() |>
  count(city_clean, place_name, sort = TRUE) |>
  print(n = 25)

city_check <- restaurants_with_place |>
  st_drop_geometry() |>
  mutate(
    yelp_says_new_orleans = city_clean == "New Orleans",
    census_says_new_orleans = place_name == "New Orleans"
  ) |>
  count(yelp_says_new_orleans, census_says_new_orleans)

print(city_check)

restaurants_with_place |>
  st_drop_geometry() |>
  filter(city_clean == "New Orleans", place_name != "New Orleans") |>
  select(business_name, address, postal_code, place_name, latitude, longitude) |>
  print(n = Inf)

selected_check <- restaurants_with_place |>
  st_drop_geometry() |>
  semi_join(selected_restaurants, by = "business_id") |>
  count(inside_official_boundary = place_name == "New Orleans")

print(selected_check)

new_orleans_map_data <- restaurants_with_place |>
  filter(place_name == "New Orleans") |>
  semi_join(st_drop_geometry(selected_restaurants), by = "business_id")

step5_map <- ggplot() +
  geom_sf(data = new_orleans_boundary, fill = "grey95", color = "grey35") +
  geom_sf(data = new_orleans_map_data, aes(color = stars), alpha = 0.7, size = 1.4) +
  scale_color_viridis_c(option = "C", limits = c(1, 5)) +
  coord_sf(xlim = c(-90.15, -89.90), ylim = c(29.88, 30.08)) +
  labs(
    title = "Seafood and Cajun/Creole Restaurants Inside the New Orleans City Boundary",
    subtitle = "Census TIGER/Line 2024 place boundary",
    color = "Business\nstars"
  ) +
  theme_minimal()

ggsave("figures/step5_city_boundary_map.png", step5_map, width = 9, height = 7, dpi = 150, bg = "white")
