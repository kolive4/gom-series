#' Aggregate OISST daily data by month or year
#'
#' @param x table of USGS daily data for one or more sites (identified by site_no)
#' @param by string, the interbval over which to aggregate - one of month or year although
#'   OISST comes natively as monthly aggregations.  So this really only handles by 
#'   year.
#' @return tibble with aggregate stats 
aggregate_oisst = function(x = read_oisst(),
                          by = c("month", "year")[2]){
  if (tolower(by[1]) == 'month'){
    # message("oisst comes as monthly aggregation - returning input")
    return(x)
  }
  
  if (nrow(x) == 0) return(x)
  fmt = switch(tolower(by[1]),
               "year" = "%Y-01-01",
               "month" = "%Y-%m-01")
  x |>
    complete_intervals_oisst(by = by) |>
    dplyr::mutate(interval_ = format(.data$date, fmt) |> as.Date(), .before = 1) |>
    dplyr::select(-dplyr::any_of(c("date", "year", "month", "week", "season"))) |>
    dplyr::group_by(region, interval_) |>
    dplyr::group_map(
      function(tbl, key, parameters = c("min", "q25", "median", "mean", "q75", "max")){
        v = sapply(parameters,
          function(p){
            vals = tbl |> 
              dplyr::pull(p) |> 
              sixnum()
            vals[[p]]
          }, simplify = FALSE) |>
          dplyr::as_tibble()
        dplyr::select(tbl, dplyr::all_of(c("interval_", "region"))) |>
          dplyr::slice(1) |>
          dplyr::bind_cols(v)
      }, .keep = TRUE) |>
    dplyr::bind_rows() |>
    dplyr::rename(date = "interval_")
}


#' Clip a table so that only complete intervals are present (for subsequent
#'  aggregation).  
#'
#' @param x tibble of oisst data
#' @param by string, the interbval over which to aggregate - one of month or year although
#'   OISST comes natively as monthly aggregations.  So this really only handles by 
#'   year.
#' @param min_count numeric defaults to 12 for year and 28 for month
#' @return tibble clipped to include only complete intervals
complete_intervals_oisst = function(x = read_oisst(), 
                                    by = c("month", "year")[2],
                                    min_count = c(month = 28, year = 12)[[by]]){

  if (tolower(by[1]) == 'month'){
    message("oisst comes as monthly aggregation - returning input")
    return(x)
  }
  if (nrow(x) == 0) return(x)
  fmt = switch(tolower(by[1]),
               "year" = "%Y-01-01",
               "month" = "%Y-%m-01")
  
  dplyr::mutate(x, interval_ = format(.data$date, fmt)) |>
    dplyr::group_by(region, interval_) |>
    dplyr::group_map(
      function(tbl, key){
        if (nrow(tbl) < min_count){
          return(NULL)
        } else {
          return(tbl)
        }
      }, .keep = TRUE) |>
    dplyr::bind_rows() |>
    dplyr::select(-dplyr::any_of("interval_"))
}


#' Read OISST data for each region
#' 
#' @param filename char the name of the file
#' @param path char the path to the file
#' @return tibble of date, region and sst params
read_oisst = function(filename =  "oisst.csv.gz",
                      path = here::here("data", "sst")){
  
  readr::read_csv(file.path(path[1], filename[1]), col_types = 'Dcnnnnnn')
}



#' Extract data from the online OISST dataset
#'
#' 
#' @param x regions to extract
#' @param path the output path
#' @param progress logical, if TRUE then show a progress bar
#' @return tibble for date, region, mean sst
fetch_oisst <- function(x = read_regions(),
                        path = here::here("data", "sst"),
                        progress = FALSE){
  if (FALSE){
    x = read_regions()
    path = here::here("data", "sst")
    progress = TRUE
  }
  # get the bounding area, pad it and rearrange orer  
  bb = sf::st_bbox(x) |>
    as.vector()
  bb = bb[c(1,3,2,4)] + c(-0.1, 0.1, -0.1, 0.1)
  
  xx <- dplyr::rowwise(x) |>
    dplyr::group_map(
      function(x, ...){
        sf::st_coordinates(x)[,1:2]
      }) |>
    rlang::set_names(x$region)
   
  X = OISST$new()
  nav = X$get_nav(bb=bb)
  dates = X$get_time()
  if (progress) pb = txtProgressBar(min = 0, max = length(dates), style = 3)

  
  r = lapply(seq_along(dates),
    function(i){
      if (progress) setTxtProgressBar(pb, i)
      #pull out the stars object for this date
      s = X$get_var(time = i, nav = nav)
      # pull out the pixels for each region - matrix ops are faster than st_extract()
      # call the summarizing function
      # trabnspose and cast as tibble
      # add in date/region info
      m <- sapply(xx, 
        function(x){
          v = stars::st_extract(s, x, na.rm = TRUE)
          sixnum(v[[1]])
        }) |>
      t() |>
      dplyr::as_tibble(rownames = "region") |>
      dplyr::mutate(date = dates[i], .before = 1)
    }) |>
    dplyr::bind_rows() |>
    readr::write_csv(file.path(path, "oisst.csv.gz"))
  if (progress) close(pb)
  X$close_nc()
  r
} # fetch_oisst



#' Export the annual (or monthly) data in a wide format
#' @param by character, one of 'year' or 'month'
#' @param x tibble or NULL, aggregated dataset.  If NULL we read it internally
#' @return wide tibble of aggregated data
export_oisst = function(by = c("year", "month")[1],
                        x = NULL){
  
  if (is.null(x)) x = aggregate_oisst(by = by)
  
  x = dplyr::mutate(x, region = region_shortnames()[region])
  
  x|>
    tidyr::pivot_wider(names_from = "region", 
                       id_cols = "date",
                       names_glue = "{region}.sst.{.value}",
                       values_from = where(is.numeric))  |>
    dplyr::arrange(date)
}



##### R6 class below ###########################################################
# Used for the purpose of harvesting chlor data from OISST as a stand alone
# Provides NCDF navigation and extraction tools
################################################################################


# R6 class for accessing OISST multiyear monthly SST
OISST = R6::R6Class("OISST",
  public = list(
    product_id = 'sst.mon.mean.nc',
    base_uri= 'http://psl.noaa.gov/thredds/dodsC/Datasets/noaa.oisst.v2.highres',
    NC = NULL,
    
    initialize = function(product_id = 'sst.mon.mean.nc',
                          base_uri = 'http://psl.noaa.gov/thredds/dodsC/Datasets/noaa.oisst.v2.highres'){
      message(sprintf("initializing: %s", product_id))
      self$product_id = product_id[1]
      self$base_uri = base_uri[1]
      self$open_nc()
    },
    
    finalize = function(){
      self$close_nc()
    },
    
    close_nc = function(){
      if (inherits(self$NC, "ncdf4")) try(ncdf4::nc_close(self$NC))
      invisible(self)
    },
    
    open_nc = function(){
      uri = file.path(self$base_uri,self$product_id)
      self$NC = try(ncdf4::nc_open(uri))
      if (inherits(self$NC, "try-error")) stop("error opening NCDF")
      invisible(self)
    },
    
    get_res = function(){
      lon = ncdf4::ncatt_get(self$NC, "lon")
      if (is.null(lon$step)){
        lon$step = abs(mean(diff(self$NC$dim$lon$vals)))
      }
      lat = ncdf4::ncatt_get(self$NC, "lat")
      if (is.null(lat$step)){
        lat$step = abs(mean(diff(self$NC$dim$lat$vals)))
      }
      c(lon$step, lat$step)
    }, # get_res
    
    get_lon = function(){
      self$NC$dim$lon$vals
    },
    
    get_lat = function(){
      self$NC$dim$lat$vals
    },
    
    get_time = function(){
      origin = as.Date(self$NC$dim$time$units,
                          format = "days since %Y-%m-%d 00:00:00")
      origin + self$NC$dim$time$vals
    }, # get_time
    
    
    get_nav = function(bb = c(-180, 180,-90, 90), varid = "sst"){
      stopifnot(varid %in% names(self$NC$var))
      
      bb = to360BB(bb)
      
      res = self$get_res()
      r2 = res/2
      lon = self$get_lon()
      lat = self$get_lat()
      closest_index = function(x, vec){
        which.min(abs(vec-x))
      } 
      
      ix = unname(sapply(bb[1:2] + c(-r2[1], r2[1]), closest_index, lon))
      nx = ix[2] - ix[1] + 1
      xmin = lon[ix[1]] - r2[1]
      xmax = lon[ix[2]] + r2[1]
      
      iy = unname(sapply(bb[3:4] + c(-r2[2], r2[2]), closest_index, lat))
      if (iy[1] >= iy[2]) {
        ny = iy[1] - iy[2] + 1
        ymin = lat[iy[1]] - r2[2]
        ymax = lat[iy[2]] + r2[1]
        iy = rev(iy)
      } else {
        ny = iy[2] - iy[1] + 1
        ymin = lat[iy[1]] - r2[2]
        ymax = lat[iy[2]] + r2[1]
      }
      
      # for bbox we still want [-180,180]
      bbox = c(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax) |>
        to180BB()
      bbox <- bbox[c("xmin", "ymin", "xmax", "ymax")]
      
      list(
        bb = bb,
        varid = varid,
        bbox = sf::st_bbox(bbox, crs = 4326),
        start = c(ix[1], iy[1],1),
        count = c(nx, ny, 1) )
    }, # get_nav
    
    get_var = function(time = 1, 
                       bbox = c(-180, 180, -90, 90), 
                       varid = 'sst',
                       nav = NULL,
                       form = c("stars", "array")[1]){
      
      if (inherits(time, "POSIXt")) time = as.Date(time)
      if (inherits(date, "Date")) time = findInterval(time, self$get_time(klass = "Date"))
      if (time <= 0) stop("time must be at or later than:", 
                          format(self$get_time()[1], "%y-%m-%d"))
      if (is.null(nav)) nav = self$get_nav(bb = bbox, varid = varid)
      
      nav$start = c(nav$start[1:2], time)
      m <- ncdf4::ncvar_get(self$NC, nav$varid,
                            start = nav$start,
                            count = nav$count)
      if (tolower(form[1]) == 'array') return(m)
      
      stars::st_as_stars(nav$bbox,
                         values = m,
                         nx = nav$count[1],
                         ny = nav$count[2]) |>
        stars::st_flip("y")
    }
    
    
  ) # public
                          
                          
)# OISST

