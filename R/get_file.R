#' @rdname files
#' @title Download File(s)
#' @description Download Dataverse File(s)
#' @details This function provides access to data files from a Dataverse entry.
#' @param file An integer specifying a file identifier; or a vector of integers specifying file identifiers; or, if \code{doi} is specified, a character string specifying a file name within the DOI-identified dataset; or an object of class \dQuote{dataverse_file} as returned by \code{\link{dataset_files}}.
#' @template ds
#' @param format A character string specifying a file format. For \code{get_file}: by default, this is \dQuote{original} (the original file format). If \dQuote{RData} or \dQuote{prep} is used, an alternative is returned. If \dQuote{bundle}, a compressed directory containing a bundle of file formats is returned. For \code{get_file_metadata}, this is \dQuote{ddi}.
#' @param vars A character vector specifying one or more variable names, used to extract a subset of the data.
#' @template envvars
#' @template dots
#' @return \code{get_file_metadata} returns a character vector containing a DDI metadata file. \code{get_file} returns a raw vector (or list of raw vectors, if \code{length(file) > 1}).
#' @examples
#' \dontrun{
#' # download file from:
#' # https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/ARKOTI
#' monogan <- get_dataverse("monogan")
#' monogan_data <- dataverse_contents(monogan)
#' d1 <- get_dataset("doi:10.7910/DVN/ARKOTI")
#' f <- get_file(d1$files$datafile$id[3])
#'
#' # check file metadata
#' m1 <- get_file_metadata("constructionData.tab", "doi:10.7910/DVN/ARKOTI")
#' m2 <- get_file_metadata(2437257)
#'
#' # retrieve file based on DOI and filename
#' f2 <- get_file("constructionData.tab", "doi:10.7910/DVN/ARKOTI")
#' f2 <- get_file(2692202)
#'
#' # retrieve file based on "dataverse_file" object
#' flist <- dataset_files(2692151)
#' get_file(flist[[2]])
#'
#' # retrieve all files in a dataset in their original format (returns a list of raw vectors)
#' file_ids <- get_dataset("doi:10.7910/DVN/CXOB4K")[['files']]$id
#' f3 <- get_file(file_ids, format = "original")
#' # read file as data.frame
#' if (require("rio")) {
#'   tmp <- tempfile(fileext = ".dta")
#'   writeBin(f, tmp)
#'   dat <- haven::read_dta(tmp)
#'
#'   # check UNF match
#'   # if (require("UNF")) {
#'   #  unf(dat) %unf% d1$files$datafile$UNF[3]
#'   # }
#' }
#' }
#' @importFrom utils unzip
#' @export
get_file <- function(
  file,
  dataset    = NULL,
  format     = c("original", "RData", "prep", "bundle"),
  # thumb    = TRUE,
  vars       = NULL,
  key        = Sys.getenv("DATAVERSE_KEY"),
  server     = Sys.getenv("DATAVERSE_SERVER"),
  ...
) {
    format <- match.arg(format)

    # single file ID
    if (is.numeric(file))
      fileid <- file

    # get file ID from 'dataset'
    if (!is.numeric(file)) {
        if (inherits(file, "dataverse_file")) {
            fileid <- get_fileid(file, key = key, server = server)
        } else if (is.null(dataset)) {
            stop("When 'file' is a character string, dataset must be specified. Or, use a global fileid instead.")
        } else {
            fileid <- get_fileid(dataset, file, key = key, server = server, ...)
        }
    } else {
      fileid <- file
    }


    # # request multiple files -----
    # if (length(fileid) > 1) {
    #     fileid <- paste0(fileid, collapse = ",")
    #     u <- paste0(api_url(server), "access/datafiles/", fileid)
    #     r <- httr::GET(u, httr::add_headers("X-Dataverse-key" = key), ...)
    #     httr::stop_for_status(r)
    #     tempf <- tempfile(fileext = ".zip")
    #     tempd <- tempfile()
    #     dir.create(tempd)
    #     on.exit(unlink(tempf), add = TRUE)
    #     on.exit(unlink(tempd), add = TRUE)
    #     writeBin(httr::content(r, as = "raw"), tempf)
    #     to_extract <- utils::unzip(tempf, list = TRUE)
    #     out <- lapply(to_extract$Name[to_extract$Name != "MANIFEST.TXT"], function(zipf) {
    #       utils::unzip(zipfile = tempf, files = zipf, exdir = tempd)
    #       readBin(file.path(tempd, zipf), "raw", n = 1e8)
    #     })
    #     return(out)
    # }

    # downloading files sequentially and add the raw vectors to a list
    out <- vector("list", length(fileid))
    for (i in 1:length(fileid)) {
        if (format == "bundle") {
            u <- paste0(api_url(server), "access/datafile/bundle/", fileid[i])
            r <- httr::GET(u, httr::add_headers("X-Dataverse-key" = key), ...)
        }
        if (format != "bundle") {
            u <- paste0(api_url(server), "access/datafile/", fileid[i])
            query <- list()
            if (!is.null(vars)) {
                query$vars <- paste0(vars, collapse = ",")
            }
            if (!is.null(format)) {
                query$format <- match.arg(format)
            }

            # request single file in non-bundle format ----
            # add query if ingesting a tab (detect from original file name)
            if (length(query) == 1 & grepl("\\.tab$", file[i])) {
                r <- httr::GET(u, httr::add_headers("X-Dataverse-key" = key), query = query, ...)
            } else {
                # do not add query if not an ingestion file
                r <- httr::GET(u, httr::add_headers("X-Dataverse-key" = key), ...)
            }
        }
        httr::stop_for_status(r)
        out[[i]] <-  httr::content(r, as = "raw")
    }
    # return the raw vector if there's a single file
    if (length(out) == 1) {
      return (out[[1]])
    }
    else {
      # return a list of raw vectors otherwise
      return (out)
    }
  }

get_file_name_from_header <- function(x) {
  gsub("\"", "", strsplit(httr::headers(x)[["content-type"]], "name=")[[1]][2])
}

#' @rdname files
#' @import xml2
#' @export
get_file_metadata <- function(
  file,
  dataset  = NULL,
  format   = c("ddi", "preprocessed"),
  key      = Sys.getenv("DATAVERSE_KEY"),
  server   = Sys.getenv("DATAVERSE_SERVER"),
  ...
) {
    # get file ID from doi
    if (!is.numeric(file)) {
      if (inherits(file, "dataverse_file")) {
        file <- get_fileid(file)
      } else if (is.null(dataset)) {
        stop("When 'file' is a character string, dataset must be specified. Or, use a global fileid instead.")
      } else {
        file <- get_fileid(dataset, file, key = key, server = server, ...)
      }
    }
    format <- match.arg(format)
    u <- paste0(api_url(server), "access/datafile/", file, "/metadata/", format)
    r <- httr::GET(u, httr::add_headers("X-Dataverse-key" = key), ...)
    httr::stop_for_status(r)
    out <- httr::content(r, as = "text", encoding = "UTF-8")
    return(out)
  }
