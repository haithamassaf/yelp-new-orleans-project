library(tidyverse)
library(jsonlite)

business_file <- "data/raw/yelp_academic_dataset_business.json"
review_file   <- "data/raw/yelp_academic_dataset_review.json"
out_dir       <- "data/new_orleans"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

business_raw <- stream_in(file(business_file), verbose = FALSE)

business <- business_raw |>
  select(
    business_id, name, address, city, state, postal_code,
    latitude, longitude, stars, review_count, categories
  ) |>
  as_tibble()
rm(business_raw); invisible(gc())

cat("All businesses:", nrow(business), "\n")

la_restaurants <- business |>
  filter(
    state == "LA",
    !is.na(categories),
    str_detect(categories, regex("Restaurants", ignore_case = TRUE))
  ) |>
  mutate(
    postal_code   = na_if(postal_code, ""),
    categories    = str_squish(categories),
    business_name = str_squish(name),
    city_clean    = str_to_title(str_squish(city))
  ) |>
  distinct(business_id, .keep_all = TRUE)

new_orleans_restaurants <- la_restaurants |>
  filter(city_clean == "New Orleans")

cat("Louisiana restaurants:", nrow(la_restaurants), "\n")
cat("New Orleans restaurants:", nrow(new_orleans_restaurants), "\n")
la_restaurants |> count(city, sort = TRUE) |> print(n = 15)

new_orleans_restaurants |>
  summarise(
    number_of_restaurants = n(),
    missing_latitude   = sum(is.na(latitude)),
    missing_longitude  = sum(is.na(longitude)),
    missing_categories = sum(is.na(categories))
  ) |>
  print()

saveRDS(new_orleans_restaurants, file.path(out_dir, "business_new_orleans.rds"), compress = "xz")
saveRDS(la_restaurants,          file.path(out_dir, "business_la_restaurants.rds"), compress = "xz")

keep_ids <- la_restaurants$business_id
chunks   <- list()
n_read   <- 0

stream_in(
  file(review_file),
  handler = function(df) {
    n_read <<- n_read + nrow(df)
    kept <- df[df$business_id %in% keep_ids,
               c("review_id", "business_id", "user_id", "stars", "date",
                 "text", "useful", "funny", "cool")]
    chunks[[length(chunks) + 1]] <<- kept
    cat(sprintf("\rread %s reviews, kept %s",
                format(n_read, big.mark = ","),
                format(sum(map_int(chunks, nrow)), big.mark = ",")))
  },
  pagesize = 100000,
  verbose = FALSE
)
cat("\n")

reviews_la <- bind_rows(chunks) |> as_tibble()
rm(chunks); invisible(gc())

reviews_new_orleans <- reviews_la |>
  semi_join(new_orleans_restaurants, by = "business_id")

cat("Reviews read:", n_read, "\n")
cat("Reviews for LA restaurants:", nrow(reviews_la), "\n")
cat("Reviews for New Orleans restaurants:", nrow(reviews_new_orleans), "\n")

saveRDS(reviews_la, file.path(out_dir, "reviews_new_orleans.rds"), compress = "xz")

glimpse(readRDS(file.path(out_dir, "business_new_orleans.rds")))
cat("Saved files:\n")
print(file.info(list.files(out_dir, full.names = TRUE, pattern = "rds$"))["size"])
