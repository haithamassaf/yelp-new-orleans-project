library(tidyverse)
library(sf)
library(tigris)
library(ggrepel)

options(tigris_use_cache = TRUE)
suppressMessages(sf_use_s2(FALSE))
dir.create("figures", showWarnings = FALSE)
dir.create("output", showWarnings = FALSE)

city_restaurants <- readRDS("data/new_orleans/selected_restaurants_neighborhoods.rds")

category_reviews <- readRDS("data/new_orleans/selected_reviews.rds") |>
  semi_join(city_restaurants, by = "business_id")

minimum_reviewer_reviews <- 5
minimum_eligible_reviews <- 20
minimum_neighborhood_restaurants <- 10

all_reviewer_summary <- category_reviews |>
  group_by(business_id) |>
  summarise(
    number_of_reviews_all_reviewers = n(),
    average_stars_all_reviewers = mean(stars),
    median_stars_all_reviewers = median(stars),
    .groups = "drop"
  )

reviewer_baselines <- category_reviews |>
  group_by(user_id) |>
  summarise(
    reviewer_mean = mean(stars),
    reviewer_median = median(stars),
    reviewer_review_count = n(),
    .groups = "drop"
  )

category_reviews_adjusted <- category_reviews |>
  left_join(reviewer_baselines, by = "user_id") |>
  mutate(
    normalized_mean_score = stars - reviewer_mean,
    normalized_median_score = stars - reviewer_median
  ) |>
  left_join(select(city_restaurants, business_id, business_name, area_name), by = "business_id")

score_restaurants <- function(adjusted_reviews) {
  adjusted_reviews |>
    group_by(business_id) |>
    summarise(
      number_of_reviews_eligible_reviewers = n(),
      average_stars_eligible_reviewers = mean(stars),
      average_normalized_score = mean(normalized_mean_score),
      median_normalized_score = median(normalized_mean_score),
      .groups = "drop"
    )
}

score_neighborhoods <- function(adjusted_reviews) {
  adjusted_reviews |>
    group_by(area_name) |>
    summarise(average_normalized_score = mean(normalized_mean_score), .groups = "drop")
}

ranked_neighborhoods <- city_restaurants |>
  count(area_name, name = "number_of_restaurants") |>
  filter(number_of_restaurants >= minimum_neighborhood_restaurants) |>
  pull(area_name)

threshold_table <- map_dfr(c(2, 3, 5, 10), function(threshold) {
  eligible_ids <- reviewer_baselines |> filter(reviewer_review_count >= threshold)
  eligible <- category_reviews_adjusted |> semi_join(eligible_ids, by = "user_id")
  neighborhood_scores <- eligible |>
    filter(area_name %in% ranked_neighborhoods) |>
    score_neighborhoods() |>
    arrange(desc(average_normalized_score))
  restaurant_scores <- score_restaurants(eligible) |>
    filter(number_of_reviews_eligible_reviewers >= minimum_eligible_reviews)

  tibble(
    minimum_reviews_per_reviewer = threshold,
    reviewers_retained = nrow(eligible_ids),
    percent_of_reviewers = 100 * nrow(eligible_ids) / nrow(reviewer_baselines),
    percent_of_reviews = 100 * nrow(eligible) / nrow(category_reviews),
    restaurants_with_20_eligible_reviews = nrow(restaurant_scores),
    top_neighborhood = neighborhood_scores$area_name[1],
    second_neighborhood = neighborhood_scores$area_name[2],
    third_neighborhood = neighborhood_scores$area_name[3]
  )
})

eligible_reviewers <- reviewer_baselines |>
  filter(reviewer_review_count >= minimum_reviewer_reviews)

eligible_adjusted_reviews <- category_reviews_adjusted |>
  semi_join(eligible_reviewers, by = "user_id")

baseline_comparison <- eligible_adjusted_reviews |>
  summarise(
    reviews = n(),
    percent_mean_score_exactly_zero = 100 * mean(normalized_mean_score == 0),
    percent_median_score_exactly_zero = 100 * mean(normalized_median_score == 0),
    correlation_mean_vs_median = cor(normalized_mean_score, normalized_median_score)
  )

restaurant_summary <- city_restaurants |>
  select(business_id, business_name, address, area_name, latitude, longitude, stars, review_count) |>
  left_join(all_reviewer_summary, by = "business_id") |>
  left_join(score_restaurants(eligible_adjusted_reviews), by = "business_id") |>
  mutate(
    raw_rank = min_rank(desc(if_else(number_of_reviews_eligible_reviewers >= minimum_eligible_reviews,
                                     average_stars_all_reviewers, NA_real_))),
    adjusted_rank = min_rank(desc(if_else(number_of_reviews_eligible_reviewers >= minimum_eligible_reviews,
                                          average_normalized_score, NA_real_)))
  ) |>
  arrange(adjusted_rank)

top_10_restaurants <- restaurant_summary |>
  filter(adjusted_rank <= 10) |>
  arrange(adjusted_rank) |>
  mutate(rank = row_number())

raw_top_10 <- restaurant_summary |>
  filter(raw_rank <= 10) |>
  arrange(raw_rank)

biggest_rank_changes <- restaurant_summary |>
  filter(!is.na(adjusted_rank)) |>
  mutate(rank_change = raw_rank - adjusted_rank) |>
  arrange(desc(abs(rank_change))) |>
  slice_head(n = 10)

restaurant_level <- restaurant_summary |>
  filter(number_of_reviews_eligible_reviewers >= minimum_eligible_reviews)

neighborhood_summary <- restaurant_level |>
  group_by(area_name) |>
  summarise(qualifying_restaurants = n(), .groups = "drop") |>
  right_join(
    city_restaurants |>
      count(area_name, name = "number_of_restaurants") |>
      filter(number_of_restaurants >= minimum_neighborhood_restaurants),
    by = "area_name"
  ) |>
  left_join(
    category_reviews_adjusted |>
      group_by(area_name) |>
      summarise(reviews_all_reviewers = n(), average_stars_all_reviewers = mean(stars), .groups = "drop"),
    by = "area_name"
  ) |>
  left_join(
    eligible_adjusted_reviews |>
      group_by(area_name) |>
      summarise(eligible_reviews = n(), average_normalized_score = mean(normalized_mean_score), .groups = "drop"),
    by = "area_name"
  ) |>
  left_join(count(top_10_restaurants, area_name, name = "top_10_restaurants"), by = "area_name") |>
  left_join(
    restaurant_level |>
      filter(average_normalized_score > 0) |>
      count(area_name, name = "above_average_restaurants"),
    by = "area_name"
  ) |>
  mutate(
    across(c(qualifying_restaurants, top_10_restaurants, above_average_restaurants), \(x) replace_na(x, 0L)),
    raw_rank = min_rank(desc(average_stars_all_reviewers)),
    adjusted_rank = min_rank(desc(average_normalized_score))
  ) |>
  select(area_name, number_of_restaurants, qualifying_restaurants, above_average_restaurants,
         top_10_restaurants, reviews_all_reviewers, average_stars_all_reviewers, raw_rank,
         eligible_reviews, average_normalized_score, adjusted_rank) |>
  arrange(adjusted_rank)

saveRDS(
  list(
    threshold_table = threshold_table,
    baseline_comparison = baseline_comparison,
    restaurant_summary = restaurant_summary,
    top_10_restaurants = top_10_restaurants,
    raw_top_10 = raw_top_10,
    biggest_rank_changes = biggest_rank_changes,
    neighborhood_summary = neighborhood_summary
  ),
  "output/analysis_results.rds"
)

raw_vs_adjusted_plot <- restaurant_level |>
  ggplot(aes(x = average_stars_all_reviewers, y = average_normalized_score)) +
  geom_hline(yintercept = 0, color = "grey70") +
  geom_point(aes(size = number_of_reviews_all_reviewers), alpha = 0.45, color = "#2c7fb8") +
  geom_point(data = top_10_restaurants, color = "#d7301f", size = 2.5) +
  geom_text_repel(data = top_10_restaurants, aes(label = business_name), size = 3, seed = 1) +
  labs(
    title = "Raw Restaurant Ratings Compared with Reviewer-Adjusted Scores",
    subtitle = paste0("Restaurants with ", minimum_eligible_reviews,
                      "+ reviews from reviewers with ", minimum_reviewer_reviews,
                      "+ reviews; top 10 in red"),
    x = "Average stars from all reviewers",
    y = "Average normalized score",
    size = "Reviews"
  ) +
  theme_minimal()

ggsave("figures/raw_vs_adjusted.png", raw_vs_adjusted_plot, width = 9, height = 6, dpi = 150, bg = "white")

rank_change_plot <- neighborhood_summary |>
  mutate(area_name = fct_reorder(area_name, -adjusted_rank)) |>
  pivot_longer(c(raw_rank, adjusted_rank), names_to = "ranking", values_to = "rank") |>
  mutate(ranking = recode(ranking, raw_rank = "All reviewers (average stars)",
                          adjusted_rank = "Reviewer-adjusted score")) |>
  ggplot(aes(x = rank, y = area_name)) +
  geom_line(aes(group = area_name), color = "grey70") +
  geom_point(aes(color = ranking), size = 3) +
  scale_x_reverse(breaks = 1:10) +
  scale_color_manual(values = c("#9ecae1", "#08519c")) +
  labs(
    title = "Neighborhood Rankings Before and After Reviewer Adjustment",
    subtitle = paste0("Neighborhoods with ", minimum_neighborhood_restaurants, "+ seafood and Cajun/Creole restaurants"),
    x = "Rank (1 = best)",
    y = NULL,
    color = NULL
  ) +
  theme_minimal() +
  theme(legend.position = "top")

ggsave("figures/neighborhood_rank_change.png", rank_change_plot, width = 9, height = 5.5, dpi = 150, bg = "white")

new_orleans_boundary <- places(state = "LA", cb = TRUE, year = 2024, progress_bar = FALSE) |>
  filter(NAME == "New Orleans") |>
  st_transform(4326)

nsa_boundaries <- st_read(
  "https://maps.nola.gov/server/rest/services/Reference/Reference_Layers/MapServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=geojson",
  quiet = TRUE
) |>
  transmute(area_name = str_to_title(GNOCDC_LAB)) |>
  left_join(select(neighborhood_summary, area_name, average_normalized_score), by = "area_name")

top_10_points <- top_10_restaurants |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)

map_box <- st_bbox(top_10_points)

final_map <- ggplot() +
  geom_sf(data = nsa_boundaries, aes(fill = average_normalized_score), color = "white", linewidth = 0.3) +
  geom_sf(data = new_orleans_boundary, fill = NA, color = "grey30", linewidth = 0.4) +
  geom_sf_text(
    data = filter(nsa_boundaries, !is.na(average_normalized_score)),
    aes(label = area_name), size = 2.6, color = "grey15", fun.geometry = st_point_on_surface
  ) +
  geom_sf(data = top_10_points, color = "black", fill = "#d7301f", shape = 21, size = 3.5) +
  geom_label_repel(
    data = top_10_points,
    aes(x = longitude, y = latitude, label = paste0(rank, ". ", business_name)),
    size = 3, seed = 2, min.segment.length = 0, box.padding = 0.5
  ) +
  scale_fill_gradient2(
    low = "#b2182b", mid = "#f7f7f7", high = "#2166ac", midpoint = 0,
    na.value = "grey88", name = "Neighborhood\nadjusted score"
  ) +
  coord_sf(
    xlim = c(map_box[["xmin"]] - 0.02, map_box[["xmax"]] + 0.02),
    ylim = c(map_box[["ymin"]] - 0.015, map_box[["ymax"]] + 0.015)
  ) +
  labs(
    title = "Top 10 Seafood and Cajun/Creole Restaurants in New Orleans",
    subtitle = paste0("Ranked by reviewer-adjusted score; neighborhoods shaded if they have ",
                      minimum_neighborhood_restaurants, "+ restaurants (grey = fewer)"),
    caption = "Boundaries: City of New Orleans Neighborhood Statistical Areas"
  ) +
  theme_void() +
  theme(plot.background = element_rect(fill = "white", color = NA))

ggsave("figures/final_top10_map.png", final_map, width = 10, height = 9, dpi = 150, bg = "white")
