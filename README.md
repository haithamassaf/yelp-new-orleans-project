# Where to Find the Best Seafood and Cajun/Creole Food in New Orleans

**Research question:** Where can someone find the best seafood and Cajun/Creole restaurants in New Orleans, and which neighborhood is best for finding them?

**[View the complete report](https://haithamassaf.github.io/yelp-new-orleans-project/yelp_new_orleans_project.html)** (the HTML file is also in [docs/](docs/yelp_new_orleans_project.html) and can be downloaded and opened in any browser)

## Executive summary

Using the Yelp Open Dataset, I studied 565 seafood and Cajun/Creole restaurants inside the New Orleans city limits and their 224,050 reviews. Restaurants are ranked by a reviewer-adjusted score (each review's stars minus that reviewer's usual rating), and neighborhoods are the City of New Orleans Neighborhood Statistical Areas. **Leonidas** (Carrollton/Riverbend) is the best neighborhood, and **Avery's On Tulane** is the top restaurant.

## Main findings

1. **Leonidas is the best neighborhood.** It ranks first whether or not ratings are adjusted for reviewer habits, and at every reviewer threshold tested.
2. **The French Quarter has the most choices but not the best odds.** It has 150 restaurants and two of the top 10, but only a third of its restaurants are rated above their reviewers' usual scores.
3. **The best restaurants are spread out.** The top 10 are in 9 different neighborhoods, including Tulane-Gravier and Gentilly Terrace.

## Top 10 restaurants

| Rank | Restaurant | Neighborhood | Avg stars (all reviewers) | Adjusted score |
|---:|---|---|---:|---:|
| 1 | Avery's On Tulane | Tulane - Gravier | 4.64 | 0.61 |
| 2 | Jaidyn's Wing Stop/Food For The Soul | Mid-City | 4.58 | 0.61 |
| 3 | Tito's Ceviche & Pisco | Uptown | 4.72 | 0.59 |
| 4 | Restaurant August | Central Business District | 4.45 | 0.55 |
| 5 | Saint John | French Quarter | 4.26 | 0.55 |
| 6 | Cafe Fleur De Lis | French Quarter | 4.10 | 0.52 |
| 7 | Gabrielle Restaurant | Treme - Lafitte | 4.47 | 0.52 |
| 8 | Brigtsen's Restaurant | Leonidas | 4.54 | 0.51 |
| 9 | Fiorella's the Original | Gentilly Terrace | 4.44 | 0.49 |
| 10 | Restaurant Rebirth | Lower Garden District | 4.64 | 0.49 |

![Top 10 restaurants map](figures/final_top10_map.png)

![Neighborhood rankings before and after reviewer adjustment](figures/neighborhood_rank_change.png)

![Raw vs. reviewer-adjusted scores](figures/raw_vs_adjusted.png)

## Files

| Path | Contents |
|---|---|
| [yelp_new_orleans_project.qmd](yelp_new_orleans_project.qmd) | Quarto source of the report |
| [docs/yelp_new_orleans_project.html](docs/yelp_new_orleans_project.html) | Rendered report (all figures embedded) |
| [R/import.R](R/import.R) | Steps 1–2: import the raw JSON, filter to New Orleans |
| [R/categories.R](R/categories.R) | Step 3: category counts and selection |
| [R/reviews.R](R/reviews.R) | Step 4: join reviews to restaurants |
| [R/spatial.R](R/spatial.R) | Step 5: spatial join with the city boundary |
| [R/geography.R](R/geography.R) | Step 6: compare geographic systems |
| [R/analysis.R](R/analysis.R) | Step 7: reviewer-adjusted scores, top 10, final map |
| [geography_analysis.md](geography_analysis.md) | Step 6 write-up (Homework 6) |
| `data/new_orleans/` | Filtered RDS files |
| `figures/` | Maps and charts |
| `output/` | Saved analysis results |

## Data

The raw Yelp JSON files are not in this repository. They are several gigabytes (GitHub rejects files over 100 MB), and Yelp's dataset terms do not allow redistributing them. The 95 MB `reviews_new_orleans.rds` is also left out.

To reproduce:

1. Download the Yelp Open Dataset (JSON) from <https://business.yelp.com/data/resources/open-dataset/>.
2. Extract `yelp_academic_dataset_business.json` and `yelp_academic_dataset_review.json` into `data/raw/`.
3. Run `Rscript R/import.R`.
4. Render the report: `quarto render yelp_new_orleans_project.qmd --output-dir docs`. This runs the other R scripts. Census and City of New Orleans boundaries are downloaded automatically.
