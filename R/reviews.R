library(tidyverse)

selected_restaurants <- readRDS("data/new_orleans/selected_restaurants.rds")
louisiana_reviews <- readRDS("data/new_orleans/reviews_new_orleans.rds")

category_reviews <- louisiana_reviews |>
  semi_join(selected_restaurants, by = "business_id") |>
  select(-text) |>
  mutate(
    review_date = as_date(ymd_hms(date)),
    review_year = year(review_date)
  ) |>
  select(-date)

category_reviews |>
  summarise(
    reviews = n(),
    reviewers = n_distinct(user_id),
    restaurants_with_reviews = n_distinct(business_id),
    first_review = min(review_date),
    last_review = max(review_date),
    average_stars = mean(stars)
  ) |>
  print()

selected_restaurants |>
  left_join(count(category_reviews, business_id, name = "reviews_in_file"), by = "business_id") |>
  summarise(
    yelp_review_count = sum(review_count),
    reviews_in_file = sum(reviews_in_file, na.rm = TRUE)
  ) |>
  print()

saveRDS(category_reviews, "data/new_orleans/selected_reviews.rds", compress = "xz")
