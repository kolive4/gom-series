Surprise
================

``` r
source("../setup.R")
```

# A toy example.

Read in the export data, but select just a few columns of interest and
filter to recent times.

``` r
x = read_export(by = 'year', 
                selection = read_target_vars(treatment = c("q25", "median", "q75")),
                standardize = FALSE) |>
  dplyr::filter(date >= as.Date("1950-01-01")) |>
  dplyr::select(date, dplyr::contains(c("nao", "amo", "gsi"))) 

plot_export(x)
```

![](README-surprise_files/figure-gfm/unnamed-chunk-2-1.png)<!-- -->

Plot without binning into surprise categories.

``` r
win = 20
s = surprise(x, win = win) |>
  dplyr::filter(date >= as.Date("1980-01-01"))
```

    ## Warning: There was 1 warning in `dplyr::mutate()`.
    ## ℹ In argument: `dplyr::across(dplyr::where(is.numeric), surprise, win = win)`.
    ## Caused by warning:
    ## ! The `...` argument of `across()` is deprecated as of dplyr 1.1.0.
    ## Supply arguments directly to `.fns` through an anonymous function instead.
    ## 
    ##   # Previously
    ##   across(a:b, mean, na.rm = TRUE)
    ## 
    ##   # Now
    ##   across(a:b, \(x) mean(x, na.rm = TRUE))

``` r
plot_surprise(s, surprise = NULL)
```

![](README-surprise_files/figure-gfm/unnamed-chunk-3-1.png)<!-- -->

And plot again but this time as categorical “-surprise”, “no surprise”,
“surprise” groups.

``` r
plot_surprise(s, surprise = 2)
```

![](README-surprise_files/figure-gfm/unnamed-chunk-4-1.png)<!-- -->

Now run again with the target variables using `median`, `q25` and `q75`.

``` r
med = read_export(by = 'year', 
                standardize = TRUE, 
                selection = read_target_vars(treatment = "median")) |>
  dplyr::filter(date >= as.Date("1970-01-01"))
g1 = plot_export(med, title = "Standardized Median by Year")

med = read_export(by = 'year', 
                standardize = FALSE, 
                selection = read_target_vars(treatment = "median")) |>
  dplyr::filter(date >= as.Date("1970-01-01"))
g2 = plot_surprise(surprise(med, win = 20), surprise = 2, title = "Median Surprise by Year")

print(g1/g2)
```

![](README-surprise_files/figure-gfm/unnamed-chunk-5-1.png)<!-- -->

``` r
q25 = read_export(by = 'year', 
                standardize = TRUE, 
                selection = read_target_vars(treatment = "q25")) |>
  dplyr::filter(date >= as.Date("1970-01-01"))
g1 = plot_export(q25, title = "Standardized Q25 by Year")

q25 = read_export(by = 'year', 
                standardize = FALSE, 
                selection = read_target_vars(treatment = "q25")) |>
  dplyr::filter(date >= as.Date("1970-01-01"))
g2 = plot_surprise(surprise(q25, win = 20), surprise = 2, title = "Q25 Surprise by Year")

print(g1/g2)
```

![](README-surprise_files/figure-gfm/unnamed-chunk-6-1.png)<!-- -->

``` r
q75 = read_export(by = 'year', 
                standardize = TRUE, 
                selection = read_target_vars(treatment = "q75")) |>
  dplyr::filter(date >= as.Date("1970-01-01"))
g1 = plot_export(q75, title = "Standardized Q75 by Year")

q75 = read_export(by = 'year', 
                standardize = FALSE, 
                selection = read_target_vars(treatment = "q75")) |>
  dplyr::filter(date >= as.Date("1970-01-01"))
g2 = plot_surprise(surprise(q75, win = 20), surprise = 2, title = "Q75 Surprise by Year")

print(g1/g2)
```

![](README-surprise_files/figure-gfm/unnamed-chunk-7-1.png)<!-- -->
