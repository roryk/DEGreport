#' Method to get the default table to use.
#' 
#' @param object [DEGSet]
#' @author Lorena Pantano
#' @rdname degDefault
#' @export
setMethod("degDefault", signature("DEGSet"), function(object) {
    slot(object, name = "default")
})

 
#' Method to get all table stored for an specific comparison
#'
#' @inheritParams degDefault
#' @param value Character to specify which table to use.
#' @param tidy Return data.frame, tibble or original class.
#' @param top Limit number of rows to return. Default: All.
#' @param ... Other parameters to pass for other methods.
#' @author Lorena Pantano
#' @rdname deg
#' @references  
#' * Testing it `top` is whole number or not comes from:
#'   https://stackoverflow.com/a/3477158
#' @export
setMethod("deg", signature("DEGSet"),
          function(object, value=NULL, tidy = NULL, top = NULL, ...) {
              df <- NULL
              stopifnot(value %in% c(NULL, names(object)))
              
              if (is.null(value))
                  df <- object[[degDefault(object)]]
              else df <- object[[value]]
              
              if (is.null(top))
                  top <- nrow(df)
              stopifnot(top%%1 == 0)
              
              if (is.null(tidy))
                  return(df %>% .[order(.[["padj"]]),] %>%
                             .[1:top,])
              if (tidy == "data.frame")
                  return(as.data.frame(df) %>% .[order(.[["padj"]]),] %>%
                             .[1:top,])
              if (tidy == "tibble")
                  return(as.data.frame(df) %>%
                             rownames_to_column("gene") %>%
                             .[order(.[["padj"]]),] %>%
                             .[1:top,] %>%
                             as_tibble)
              stop("Not supported format, ", tidy)
          })

.filterTable <- function(df, direction, fcn, fc , fdr, padj){
    filterOut <- NULL
    if (is.null(direction))
        filterOut <- abs(df[[fcn]]) > fc & df[[fdr]] < padj
    else if (direction == "up")
        filterOut <- df[[fcn]] > fc & df[[fdr]] < padj
    else if (direction == "down")
        filterOut <- df[[fcn]] < (-1L * fc) & df[[fdr]] < padj
    else
        stop("Value ", direction, " is not valid: NULL, down, up.")
    return(filterOut)
}

#' Method to get the significant genes
#' 
#' Function to get the features that are significant
#' according to some thresholds from a [DEGSet],
#' [DESeq2::DESeqResults] and [edgeR::topTags].
#' 
#' @author Lorena Pantano
#' @inheritParams degDefault
#' @param padj Cutoff for the FDR column.
#' @param fc Cutoff for the log2FC column.
#' @param direction Whether to take down/up/ignore. Valid arguments are
#'   down, up and NULL.
#' @param full Whether to return full table or not.
#' @param newFDR Whether to recalculate the FDR or not.
#'   See https://support.bioconductor.org/p/104059/#104072.
#'   Only used when a list is giving to the method.
#' @param ... Passed to [deg]. Default: value = NULL.
#'   Value can be 'raw', 'shrunken'.
#' @rdname significants
#' @examples
#' library(DESeq2)
#' library(dplyr)
#' dds <- makeExampleDESeqDataSet(betaSD=1)
#' colData(dds)[["treatment"]] <- sample(colData(dds)[["condition"]], 12)
#'   design(dds) <-  ~ condition + treatment
#' dds <- DESeq(dds)
#' res <- degComps(dds, contrast = list("treatment_B_vs_A",
#'                                      c("condition", "A", "B")))
#' significants(res, full = TRUE) %>% head
#' significants(res, full = TRUE, padj = 1) %>% head # all genes
#' @export
setMethod("significants", signature("DEGSet"),
          function(object, padj = 0.05, fc = 0,
                   direction = NULL, full = FALSE, ...){
              fc <- abs(fc)
              df <-  as.data.frame(deg(object, ...))
              filterOut <- .filterTable(df, direction,
                                        "log2FoldChange", fc,
                                        "padj", padj)
              df <- df %>%
                  rownames_to_column("gene") %>%
                  subset(., filterOut) %>%
                  .[order(abs(.[["log2FoldChange"]]), decreasing = TRUE),]
              if (full)
                  return(as_tibble(df))
              return(df[["gene"]])
          })

#' @rdname significants
#' @export
setMethod("significants", signature("DESeqResults"),
          function(object, padj = 0.05, fc = 0,
                   direction = NULL, full = FALSE, ...){
              fc <- abs(fc)
              df <-  as.data.frame(object)
              filterOut <- .filterTable(df, direction,
                                        "log2FoldChange", fc,
                                        "padj", padj)
              
              df <- df %>%
                  rownames_to_column("gene") %>%
                  subset(., filterOut) %>%
                  .[order(abs(.[["log2FoldChange"]]), decreasing = TRUE),]
              
              if (full)
                  return(as_tibble(df))
              return(df[["gene"]])
              
          })

#' @rdname significants
#' @export
setMethod("significants", signature("TopTags"),
          function(object, padj = 0.05, fc = 0,
                   direction = NULL, full = FALSE, ...){
              fc <- abs(fc)
              df <-  as.data.frame(object)
              filterOut <- .filterTable(df, direction,
                                        "logFC", fc,
                                        "FDR", padj)

              df <- df %>%
                  rownames_to_column("gene") %>%
                  subset(., filterOut) %>%
                  rename(padj = FDR, log2FoldChange = logFC) %>% 
                  .[order(abs(.[["logFC"]]), decreasing = TRUE),]
              if (full)
                  return(as_tibble(df))
              return(df[["gene"]])
              
          })

.supported <- function(x){
    return(class(x) %in% c("DEGSet", "DESeqResults"))
}

.get_contrast_name <- function(x){
    if (class(x) == "DEGSet"){
        table = deg(x)
    }else if (class(x) == "DESeqResults"){
        table = x
    }else{
        stop("Format not supported: ", class(x))
    }
    contrast <- slot(table, "elementMetadata") %>% 
        .[["description"]] %>% 
        .[2]
    str_split(contrast, ": ")[[1]][2] %>%
        make.names
}

#' @rdname significants
#' @export
setMethod("significants", signature("list"),
          function(object, padj = 0.05, fc = 0,
                   direction = NULL, full = FALSE,
                   newFDR = FALSE, ...){
              if (!full){
                  if (newFDR){
                      selected <- lapply(object, significants, 
                                         padj = 1, fc = 0,
                                         full = TRUE) %>%
                          bind_rows() %>% 
                          mutate(fdr = p.adjust(padj, "fdr")) %>% 
                          subset(., .filterTable(., direction,
                                                 "log2FoldChange", fc,
                                                 "fdr", padj)) %>%
                          .[["gene"]] %>% 
                          unique()
                  }else{
                      selected <- lapply(object, significants, 
                                         padj = padj, fc = fc,
                                         direction = direction) %>%
                          unlist() %>% 
                          unique()
                  }
                  return(selected)
              }else{
                  object <- object[sapply(object, .supported)]
                  if (length(object) == 0){
                      message("Only DEGSet and DESeqResults objects are used.")
                      stop("No compatible objects remained.")
                  }
                  different_names <- unique(names(object))
                  if (length(different_names) != length(object))
                      different_names <- sapply(object, .get_contrast_name) %>% 
                      unique()
                  if(length(different_names) != length(object))
                      warning("Contrast names are repeated inside the list.")
                  names(object) <- different_names
                  df <- lapply(different_names, function(x){
                      top <- significants(object[[x]], padj = padj, fc = fc,
                                          direction = direction,
                                          full = full) 
                      top_renamed <- top %>% 
                          .[, c("log2FoldChange", "padj")] %>% 
                          set_colnames(paste(colnames(.), 
                                             x,
                                             sep = "_"))
                      top_renamed[["gene"]] <- top[["gene"]]
                      gather(top_renamed, "variable", "value", -gene)
                      }) %>% bind_rows() %>% 
                      distinct() %>% 
                      spread(., "variable", "value") %>% 
                      as_tibble()
                  return(df)
              }
          })

#' @rdname DEGSet
#' @export
setMethod("as.DEGSet", signature("TopTags"),
          function(object, default = "raw", extras = NULL){
    name <- paste("contrast_", object[["comparison"]], collapse = "-")
    df <- as.data.frame(object) %>% set_colnames(c("log2FoldChange",
                                                "baseMean",
                                                "pvalue",
                                                "padj")) %>%
        DataFrame
    news <- lapply(extras, function(e){
        if (class(e) == "TopTags")
            return(as.data.frame(e) %>% set_colnames(c("log2FoldChange",
                                                       "baseMean",
                                                       "pvalue",
                                                       "padj")) %>%
                       DataFrame)
        stop(class(e), " is not a TopTags object.")
    })
    names(news) <- names(extras)
    l <- c(list(raw = df), news)
    if (!(default  %in% names(l))){
        message(default, " not found in names of list:", paste(names(l)))
        message("Set it up to raw")
        default == "raw"
    }
    dge <- new("DEGSet", l,
               default = default)
    attr(dge, "comparison") <- name
    dge
})

#' @rdname DEGSet
#' @export
setMethod("as.DEGSet", signature("data.frame"),
          function(object, contrast, default = "raw", extras = NULL){
              stopifnot(!is.null(contrast))
              cols <- c("logFC", "AveExpr", "P.Value", "adj.P.Val")
              stopifnot(cols  %in% names(object))
              name <- contrast
              df <- as.data.frame(object)[,cols] %>%
                  set_colnames(c("log2FoldChange",
                                 "baseMean",
                                 "pvalue",
                                 "padj")) %>%
                  DataFrame
              news <- lapply(extras, function(e){
                  if (class(e) == "data.frame"){
                      stopifnot(cols  %in% names(object))
                      return(as.data.frame(e)[,cols] %>% 
                                 set_colnames(c("log2FoldChange",
                                                "baseMean",
                                                "pvalue",
                                                "padj")) %>%
                                 DataFrame)
                  }
              })
              names(news) <- names(extras)
              l <- c(list(raw = df), news)
              if (!(default  %in% names(l))){
                  message(default, " not found in names of list:", paste(names(l)))
                  message("Set it up to raw")
                  default == "raw"
              }
              dge <- new("DEGSet", l,
                         default = "raw")
              attr(dge, "comparison") <- name
              dge
          })

#' @rdname DEGSet
#' @export
setMethod("as.DEGSet", signature("DESeqResults"),
          function(object, default = "shrunken", extras = NULL){
    name <- slot(slot(object, "elementMetadata"), "listData")[[2L]][2L]
    name <- strsplit(name, ":")[[1L]][2L] %>%
        gsub(" ", "", .)
    df <- DataFrame(object)
    news <- lapply(extras, function(e){
        if (class(e) == "DESeqResults")
            return(DataFrame(e))
        stop(class(e), " is not a DESeqResults object.")
    })
    names(news) <- names(extras)
    l <- c(list(raw = df), news)
    if (!(default  %in% names(l))){
        message(default, " not found in names of list:", paste(names(l)))
        message("Set it up to raw")
        default == "raw"
    }
    dge <- new("DEGSet", l,
               default = default)
    attr(dge, "comparison") <- name
    .validate(dge)
    dge
})

# setMethod("DEGSetFromList", signature("list"),
#           function(object, default = "shrunken"){
#               dgeList <- lapply(object, function(o){
#                   if (class(o) == "DESeqResults")
#                       return(DEGSetFromDESeq2())
#                   else if (class(o) == "TopTags")
#                       return(DEGSetFromDESeq2())
#                   else
#                       message(class(o), " not supported, skipping.")
#               })
#               if (!is.null(names(list)))
#                 names(dgeList) <- names(list)
#               dgeList
# })
