library(tidyverse)

new_orleans_restaurants <- readRDS("data/new_orleans/business_new_orleans.rds")

restaurant_categories <- new_orleans_restaurants |>
  select(business_id, categories) |>
  separate_rows(categories, sep = ",") |>
  mutate(category = str_to_lower(str_squish(categories))) |>
  filter(category != "") |>
  distinct(business_id, category)

category_counts <- restaurant_categories |>
  filter(!category %in% c("restaurants", "food")) |>
  count(category, name = "number_of_restaurants", sort = TRUE)

print(category_counts, n = 25)

category_pairs <- restaurant_categories |>
  inner_join(restaurant_categories, by = "business_id", suffix = c("_1", "_2"),
             relationship = "many-to-many") |>
  filter(category_1 < category_2,
         !category_1 %in% c("restaurants", "food"),
         !category_2 %in% c("restaurants", "food")) |>
  count(category_1, category_2, name = "restaurants_with_both", sort = TRUE)

selected_categories <- c("seafood", "cajun/creole", "seafood markets")

category_pairs |>
  filter(category_1 %in% selected_categories | category_2 %in% selected_categories) |>
  print(n = 20)

category_pairs |>
  filter(category_1 %in% selected_categories, category_2 %in% selected_categories) |>
  print()

selected_flags <- restaurant_categories |>
  filter(category %in% selected_categories) |>
  mutate(value = TRUE) |>
  pivot_wider(names_from = category, values_from = value, values_fill = FALSE)

selected_restaurants <- new_orleans_restaurants |>
  inner_join(selected_flags, by = "business_id") |>
  mutate(categories_matched = `seafood` + `cajun/creole` + `seafood markets`)

selected_restaurants |>
  summarise(
    number_of_restaurants = n(),
    seafood = sum(`seafood`),
    cajun_creole = sum(`cajun/creole`),
    seafood_markets = sum(`seafood markets`),
    matched_two_or_more = sum(categories_matched >= 2),
    average_stars = mean(stars),
    total_reviews = sum(review_count)
  ) |>
  print()

zip_spread <- selected_restaurants |>
  count(postal_code, name = "number_of_restaurants", sort = TRUE)

print(zip_spread, n = 30)

zip_spread |>
  summarise(
    zip_codes = n(),
    zip_codes_with_10_or_more = sum(number_of_restaurants >= 10)
  ) |>
  print()

saveRDS(selected_restaurants, "data/new_orleans/selected_restaurants.rds", compress = "xz")
