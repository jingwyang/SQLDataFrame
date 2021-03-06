.join_union_prepare <- function(x, y)
{
    if (is(tblData(x)$ops, "op_double") | is(tblData(x)$ops, "op_single")) {
        con <- .con_SQLDataFrame(x)
        tblx <- .open_tbl_from_connection(con, "main", x)
        
        if (is(tblData(y)$ops, "op_double") | is(tblData(y)$ops, "op_single")) {
            ## attach all databases from y except "main", which is
            ## temporary connection from "union" or "join"
            dbs <- .dblist(con)
            cony <- .con_SQLDataFrame(y)
            tbly <- .extract_tbl_from_SQLDataFrame(y)
            dbsy <- .dblist(cony)[-1,]
            
            idx <- match(paste(dbsy$name, dbsy$file, sep=":"),
                         paste(dbs$name, dbs$file, sep=":"))
            idx <- which(!is.na(idx))          
            if (length(idx)) dbsy <- dbsy[-idx, ]
            for (i in seq_len(nrow(dbsy))) {
                .attach_database(con, dbsy[i, "file"], dbsy[i, "name"])
            }
            ## open the lazy tbl from new connection
            sql_cmd <- dbplyr::db_sql_render(cony, tbly)
            tbly <- tbl(con, sql_cmd)
        } else {
            tbly <- .attachMaybe_and_open_tbl_in_new_connection(con, y)
        }
    } else if (is(tblData(y)$ops, "op_double") | is(tblData(y)$ops, "op_single"))
    {  
        con <- .con_SQLDataFrame(y)
        tbly <- .open_tbl_from_connection(con, "main", y)
        tblx <- .attachMaybe_and_open_tbl_in_new_connection(con, x)
    } else {
        dbname <- tempfile(fileext = ".db")
        con <- DBI::dbConnect(RSQLite::SQLite(), dbname = dbname)
        tblx <- .attachMaybe_and_open_tbl_in_new_connection(con, x)
        tbly <- .attachMaybe_and_open_tbl_in_new_connection(con, y)
    }
    return(list(tblx, tbly))
}

.attachMaybe_and_open_tbl_in_new_connection <- function(con, sdf) {
    dbs <- .dblist(con)
    aux <- dbs[match(dbname(sdf), dbs$file), "name"]
    if (is.na(aux))
        aux <- .attach_database(con, dbname(sdf))
    res_tbl <- .open_tbl_from_connection(con, aux, sdf)
    return(res_tbl)
}
.dblist <- function(con) {
    res <- dbGetQuery(con, "PRAGMA database_list")
    return(res)
}
.dblist_SQLDataFrame <- function(sdf) {
    con <- .con_SQLDataFrame(sdf)
    .dblist(con)
}
.attach_database <- function(con, dbname, aux = NULL) {
    if (is.null(aux))
        aux <- dplyr:::random_table_name()
    dbExecute(con, paste0("ATTACH '", dbname, "' AS ", aux))
    return(aux)
}
.open_tbl_from_connection <- function(con, aux, sdf) {
    if (aux == "main") {
        tblx <- .extract_tbl_from_SQLDataFrame(sdf)
    } else {
        auxSchema <- in_schema(aux, ident(dbtable(sdf)))
        tblx <- tbl(con, auxSchema)
        tblx <- .extract_tbl_from_SQLDataFrame_indexes(tblx, sdf)
    }
    return(tblx)
}

.doCompatibleFunction <- function(x, y, ..., FUN) {
    tbls <- .join_union_prepare(x, y)
    tbl.out <- FUN(tbls[[1]], tbls[[2]], ...)
    dbnrows <- tbl.out %>% summarize(n=n()) %>% pull(n)

    out <- BiocGenerics:::replaceSlots(x, tblData = tbl.out,
                                       dbnrows = dbnrows,
                                       indexes = vector("list", 2))
    return(out)
}

#########################
## left_join, inner_join
#########################

#' join \code{SQLDataFrame} together
#' @name left_join
#' @rdname joinSQLDataFrame
#' @description *_join functions for \code{SQLDataFrame} objects. Will
#'     preserve the duplicate rows for the input argument `x`.
#' @aliases left_join left_join,SQLDataFrame-method
#' @param x \code{SQLDataFrame} objects to join.
#' @param y \code{SQLDataFrame} objects to join.
#' @param by A character vector of variables to join by.  If ‘NULL’,
#'     the default, ‘*_join()’ will do a natural join, using all
#'     variables with common names across the two tables. See
#'     \code{?dplyr::join} for details.
#' @param copy see \code{?dplyr::join} for details. 
#' @param suffix A character vector of length 2 specify the suffixes
#'     to be added if there are non-joined duplicate variables in ‘x’
#'     and ‘y’. Default values are ".x" and ".y".See
#'     \code{?dplyr::join} for details.
#' @param ... additional arguments to be passed.
#' @return A \code{SQLDataFrame} object.
#' @export
#' @examples
#' db1 <- system.file("extdata/test.db", package = "SQLDataFrame")
#' db2 <- system.file("extdata/test1.db", package = "SQLDataFrame")
#' obj1 <- SQLDataFrame(dbname = db1,
#'                      dbtable = "state",
#'                      dbkey = c("region", "population"))
#' obj2 <- SQLDataFrame(dbname = db2,
#'                      dbtable = "state1",
#'                      dbkey = c("region", "population"))
#'
#' obj1_sub <- obj1[1:10, 1:2]
#' obj2_sub <- obj2[8:15, 2:3]
#'
#' left_join(obj1_sub, obj2_sub)
#' inner_join(obj1_sub, obj2_sub)
#' semi_join(obj1_sub, obj2_sub)
#' anti_join(obj1_sub, obj2_sub)

left_join.SQLDataFrame <- function(x, y, by = NULL,
                                   copy = FALSE,
                                   suffix = c(".x", ".y"), ...) 
{
    out <- .doCompatibleFunction(x, y, by = by, copy = copy,
                                 suffix = suffix,
                                 auto_index = FALSE,
                                 FUN = dbplyr:::left_join.tbl_lazy)
    if (!identical(dbkey(x), dbkey(y))) {
        dbkey(out) <- c(dbkey(x), dbkey(y))
    } else {
        dbrnms <- unique(ROWNAMES(x))
        ind <- match(ROWNAMES(x), dbrnms)
        ind <- ind[!is.na(ind)]
        ridx <- NULL
        if (!identical(ind, seq_len(nrow(x)))) {
            ridx <- ind
        }
        BiocGenerics:::replaceSlots(
                           out, dbconcatKey = dbrnms,
                           indexes = list(ridx, NULL))
    }
}

#' @name inner_join
#' @rdname joinSQLDataFrame
#' @aliases inner_join inner_join,SQLDataFrame-method
#' @export
inner_join.SQLDataFrame <- function(x, y, by = NULL,
                                    copy = FALSE,
                                    suffix = c(".x", ".y"), ...) 
{
    out <- .doCompatibleFunction(x, y, by = by, copy = copy,
                                 suffix = suffix,
                                 auto_index = FALSE,
                                 FUN = dbplyr:::inner_join.tbl_lazy)

    if (!identical(dbkey(x), dbkey(y))) {
        dbkey(out) <- c(dbkey(x), dbkey(y))
    } else {
        dbrnms <- intersect(ROWNAMES(x), ROWNAMES(y))
        ind <- match(ROWNAMES(x), dbrnms)
        ind <- ind[!is.na(ind)]
        ridx <- NULL
        if (!identical(ind, normalizeRowIndex(out))) {
            ridx <- ind
        }
        out <- BiocGenerics:::replaceSlots(
                                  out, dbconcatKey = dbrnms,
                                  indexes = list(ridx, NULL))
    }
    out
}

#########################
## semi_join, anti_join (filtering joins)
#########################

## for "semi_join", the new tblData()$ops is "op_semi_join".
## see show_query(tblData()), "...WHERE EXISTS..."
## semi_join is similar to `inner_join`, but doesn't add new columns.

#' @name semi_join
#' @rdname joinSQLDataFrame
#' @aliases semi_join semi_join,SQLDataFrame-method
#' @export
semi_join.SQLDataFrame <- function(x, y, by = NULL,
                                   copy = FALSE,
                                   suffix = c(".x", ".y"), ...) 
{
    out <- .doCompatibleFunction(x, y, by = by, copy = copy,
                                 suffix = suffix,
                                 auto_index = FALSE,
                                 FUN = dbplyr:::semi_join.tbl_lazy)
    if (!identical(dbkey(x), dbkey(y))) {
        dbkey(out) <- c(dbkey(x), dbkey(y))
    } else {        
        dbrnms <- intersect(ROWNAMES(x), ROWNAMES(y))
        ind <- match(ROWNAMES(x), dbrnms)
        ind <- ind[!is.na(ind)]
        ridx <- NULL
        if (!identical(ind, normalizeRowIndex(out))) {
            ridx <- ind
        }
        out <- BiocGenerics:::replaceSlots(
                                  out, dbconcatKey = dbrnms,
                                  indexes = list(ridx, NULL))
    }
    out
}

## for "anti_join", the new tblData()$ops is still "op_semi_join"
## see show_query(tblData()), "...WHERE NOT EXISTS..."

#' @name anti_join
#' @rdname joinSQLDataFrame
#' @aliases anti_join anti_join,SQLDataFrame-method
#' @export
anti_join.SQLDataFrame <- function(x, y, by = NULL,
                                   copy = FALSE,
                                   suffix = c(".x", ".y"), ...) 
{
    out <- .doCompatibleFunction(x, y, by = by, copy = copy,
                                 suffix = suffix,
                                 auto_index = FALSE,
                                 FUN = dbplyr:::anti_join.tbl_lazy)
    if (!identical(dbkey(x), dbkey(y))) {
        dbkey(out) <- c(dbkey(x), dbkey(y))
    } else {
        dbrnms <- setdiff(ROWNAMES(x), ROWNAMES(y))
        ind <- match(ROWNAMES(x), dbrnms)
        ind <- ind[!is.na(ind)]
        ridx <- NULL
        if (!identical(ind, normalizeRowIndex(out))) {
            ridx <- ind
        }
        BiocGenerics:::replaceSlots(
                           out, dbconcatKey = dbrnms,
                           indexes = list(ridx, NULL))
    }
}

