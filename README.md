# Yelp New Orleans Restaurant Analysis

## Data

The raw Yelp files are not included in this repository because of their size.

1. Download the Yelp Open Dataset (JSON) from <https://business.yelp.com/data/resources/open-dataset/>.
2. Extract `yelp_academic_dataset_business.json` and `yelp_academic_dataset_review.json` into `data/raw/`.
3. Run `Rscript R/import.R`.

This creates `business_new_orleans.rds`, `business_la_restaurants.rds`, and `reviews_new_orleans.rds` in `data/new_orleans/`.
