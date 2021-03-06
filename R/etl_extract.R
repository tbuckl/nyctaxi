#' Extract NYC Taxi Trip Data from data from NYC Taxi & Limousine Commission
#' 
#' @import etl
#' @importFrom stringr str_pad
#' @export 
#' @details extract NYC Yellow taxi trip data from Jan 2009 to the most recent month,
#' Green taxi trip data from Aug 2013 to the most recent month data from NYC Taxi & Limousine Commission, 
#' Uber trip data from April to September 2014 and January to June 2015,
#' Lyft weekly-aggregated data from 2015 to the most recent week.
#' @param obj an etl object 
#' @param years a numeric vector giving the years. The default is the most recent year.
#' @param months a numeric vector giving the months. The default is January to December.
#' @param type a character variable giving the type of data the user wants to download. 
#' There are four options: yellow (meaning yellow taxi data), 
#' green (meaning green taxi data), uber, and lyft. Users can only choose one transportation at a time.
#' The default is \code{yellow}.
#' @param ... arguments passed to \code{\link[etl]{smart_download}}
#' @seealso \code{\link[etl]{etl_extract}}
#' @examples 
#' 
#' 
#' \dontrun{
#' taxi <- etl("nyctaxi", dir = "~/Desktop/nyctaxi")
#' taxi %>% 
#'    etl_extract(years = 2014, months = 1:12, type = c("uber")) %>% 
#'    etl_transform(years = 2015, months = 1, type = c("green")) %>% 
#'    etl_load(years = 2015, months = 1, type = c("green")) 
#' }

etl_extract.etl_nyctaxi <- function(obj, years = as.numeric(format(Sys.Date(),'%Y')), 
                                    months = 1:12, 
                                    type  = "yellow",...) {
  #TAXI YELLOW-----------------------------------------------------------------------
  taxi_yellow <- function(obj, years, months,...) {
    message("Extracting raw yellow taxi data...")
    remote <- etl::valid_year_month(years, months, begin = "2009-01-01") %>%
      mutate_(src = ~file.path("https://s3.amazonaws.com/nyc-tlc/trip+data", 
                               paste0("yellow", "_tripdata_", year, "-",
                                      stringr::str_pad(month, 2, "left", "0"), ".csv"))) 
    tryCatch(expr = etl::smart_download(obj, remote$src, ...),
             error = function(e){warning(e)}, 
             finally = warning("Only the following data are availabel on TLC:
                               Yellow taxi data: 2009 Jan - last month"))} 
  #TAXI GREEN-----------------------------------------------------------------------
  taxi_green <- function(obj, years, months,...) {
    message("Extracting raw green taxi data...")
    remote <- etl::valid_year_month(years, months, begin = "2013-08-01") %>%
      mutate_(src = ~file.path("https://s3.amazonaws.com/nyc-tlc/trip+data", 
                               paste0("green", "_tripdata_", year, "-",
                                      stringr::str_pad(month, 2, "left", "0"), ".csv")))
    tryCatch(expr = etl::smart_download(obj, remote$src, ...),
             error = function(e){warning(e)}, 
             finally = warning("Only the following data are availabel on TLC:
                               Green taxi data: 2013 Aug - last month"))} 
  #UBER-----------------------------------------------------------------------
  uber <- function(obj, years, months,...) {
    message("Extracting raw uber data...")
    raw_month_2014 <- etl::valid_year_month(years = 2014, months = 4:9)
    raw_month_2015 <- etl::valid_year_month(years = 2015, months = 1:6)
    raw_month <- bind_rows(raw_month_2014, raw_month_2015)
    path = "https://raw.githubusercontent.com/fivethirtyeight/uber-tlc-foil-response/master/uber-trip-data"
    remote <- etl::valid_year_month(years, months)
    remote_small <- intersect(raw_month, remote)
    if (2015 %in% remote_small$year && !(2014 %in% remote_small$year)){
      #download 2015 data
      message("Downloading Uber 2015 data...")
      etl::smart_download(obj, "https://github.com/fivethirtyeight/uber-tlc-foil-response/raw/master/uber-trip-data/uber-raw-data-janjune-15.csv.zip",...)}
    else if (2015 %in% remote_small$year && 2014 %in% remote_small$year) {
      #download 2015 data
      message("Downloading Uber 2015 data...")
      etl::smart_download(obj, "https://github.com/fivethirtyeight/uber-tlc-foil-response/raw/master/uber-trip-data/uber-raw-data-janjune-15.csv.zip",...)
      #download 2014 data
      small <- remote_small %>%
        filter_(~year == 2014) %>%
        mutate_(month_abb = ~tolower(month.abb[month]),
                src = ~file.path(path, paste0("uber-raw-data-",month_abb,substr(year,3,4),".csv")))
      message("Downloading Uber 2014 data...")
      etl::smart_download(obj, small$src,...) 
    } else if (2014 %in% remote_small$year && !(2015 %in% remote_small$year)) {
      message("Downloading Uber 2014 data...")
      #file paths
      small <- remote_small %>%
        mutate_(month_abb = ~tolower(month.abb[month]),
                src = ~file.path(path, paste0("uber-raw-data-",month_abb,substr(year,3,4),".csv")))
      etl::smart_download(obj, small$src,...)}
    else {warning("The Uber data you requested are not currently available. Only data from 2014/04-2014/09 and 2015/01-2015/06 are available...")}
    } 
  #LYFT-----------------------------------------------------------------------
  lyft <- function(obj, years, months,...){
    message("Extracting raw lyft data...")
    #check if the week is valid
    valid_months <- etl::valid_year_month(years, months, begin = "2015-01-01")
    base_url = "https://data.cityofnewyork.us/resource/edp9-qgv4.csv"
    valid_months <- valid_months %>%
      mutate_(new_filenames = ~paste0("lyft-", year, ".csv")) %>%
      mutate_(drop = TRUE)
    #only keep one data set per year
    year <- valid_months[1,1]
    n <- nrow(valid_months)
    for (i in 2:n) {
      if(year == valid_months[i-1,1]) {
        valid_months[i,6] <- FALSE
        year <- valid_months[i+1,1]
      } else {
        valid_months[i,6] <- TRUE
        year <- valid_months[i+1,1]}
      }
    row_to_keep = valid_months$drop
    valid_months <- valid_months[row_to_keep,]
    
    #download lyft files, try two different methods
    first_try<-tryCatch(
      download_nyc_data(obj, base_url, valid_months$year, n = 50000,
                        names = valid_months$new_filenames),
      error = function(e){warning(e)},finally = 'method = "libcurl" fails')
  }
  
  if (type == "yellow"){taxi_yellow(obj, years, months,...)} 
  else if (type == "green"){taxi_green(obj, years, months,...)}
  else if (type == "uber"){uber(obj, years, months,...)}
  else if (type == "lyft"){lyft(obj, years, months,...)}
  else {message("The type you chose does not exit...")}
  
  invisible(obj)
}

