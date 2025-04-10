#' Rename parameters in brmsfit objects
#'
#' Rename parameters within the \code{stanfit} object
#' after model fitting to ensure reasonable parameter names. This function is
#' usually called automatically by \code{\link{brm}} and users will rarely be
#' required to call it themselves.
#'
#' @param x A \code{brmsfit} object.
#' @return A \code{brmsfit} object with adjusted parameter names.
#'
#' @details
#' Function \code{rename_pars} is a deprecated alias of \code{rename_pars}.
#'
#' @examples
#' \dontrun{
#' # fit a model manually via rstan
#' scode <- stancode(count ~ Trt, data = epilepsy)
#' sdata <- standata(count ~ Trt, data = epilepsy)
#' stanfit <- rstan::stan(model_code = scode, data = sdata)
#'
#' # feed the Stan model back into brms
#' fit <- brm(count ~ Trt, data = epilepsy, empty = TRUE)
#' fit$fit <- stanfit
#' fit <- rename_pars(fit)
#' summary(fit)
#' }
#'
#' @export
rename_pars <- function(x) {
  if (!length(x$fit@sim)) {
    return(x)
  }
  bframe <- brmsframe(x$formula, x$data)
  pars <- variables(x)
  # find positions of parameters and define new names
  to_rename <- c(
    rename_predictor(bframe, pars = pars, prior = x$prior),
    rename_re(bframe, pars = pars),
    rename_Xme(bframe, pars = pars)
  )
  # perform the actual renaming in x$fit@sim
  x <- save_old_par_order(x)
  x <- do_renaming(x, to_rename)
  x$fit <- repair_stanfit(x$fit)
  x <- compute_quantities(x)
  x <- reorder_pars(x)
  x
}

# helps in renaming parameters after model fitting
# @return a list whose elements can be interpreted by do_renaming
rename_predictor <- function(x, ...) {
  UseMethod("rename_predictor")
}

#' @export
rename_predictor.default <- function(x, ...) {
  NULL
}

#' @export
rename_predictor.mvbrmsterms <- function(x, pars, ...) {
  out <- list()
  for (i in seq_along(x$terms)) {
    c(out) <- rename_predictor(x$terms[[i]], pars = pars, ...)
  }
  if (x$rescor) {
    rescor_names <- get_cornames(
      x$responses, type = "rescor", brackets = FALSE
    )
    lc(out) <- rlist(grepl("^rescor\\[", pars), rescor_names)
  }
  out
}

#' @export
rename_predictor.brmsterms <- function(x, ...) {
  out <- list()
  for (dp in names(x$dpars)) {
    c(out) <- rename_predictor(x$dpars[[dp]], ...)
  }
  for (nlp in names(x$nlpars)) {
    c(out) <- rename_predictor(x$nlpars[[nlp]], ...)
  }
  if (is.formula(x$adforms$mi)) {
    c(out) <- rename_Ymi(x, ...)
  }
  c(out) <- rename_thres(x, ...)
  c(out) <- rename_bhaz(x, ...)
  c(out) <- rename_family_cor_pars(x, ...)
  out
}

# helps in renaming parameters of additive predictor terms
# @param pars vector of all parameter names
#' @export
rename_predictor.bframel <- function(x, ...) {
  c(rename_fe(x, ...),
    rename_sm(x, ...),
    rename_cs(x, ...),
    rename_sp(x, ...),
    rename_gp(x, ...),
    rename_ac(x, ...))
}

# helps in renaming fixed effects parameters
rename_fe <- function(bframe, pars, prior, ...) {
  stopifnot(is.bframel(bframe))
  out <- list()
  fixef <- bframe$frame$fe$vars_stan
  if (!length(fixef)) {
    return(out)
  }
  px <- check_prefix(bframe)
  p <- usc(combine_prefix(px))
  b <- paste0("b", p)
  pos <- grepl(paste0("^", b, "\\["), pars)
  bnames <- paste0(b, "_", fixef)
  lc(out) <- rlist(pos, bnames)
  c(out) <- rename_prior(b, pars, names = fixef)
  if (has_special_prior(prior, bframe, class = "b")) {
    sdb <- paste0("sdb", p)
    pos <- grepl(paste0("^", sdb, "\\["), pars)
    sdb_names <- paste0(sdb, "_", fixef)
    lc(out) <- rlist(pos, sdb_names)
  }
  out
}

# helps in renaming special effects parameters
rename_sp <- function(bframe, pars, prior, ...) {
  stopifnot(is.bframel(bframe))
  out <- list()
  spframe <- bframe$frame$sp
  if (!nrow(spframe)) {
    return(out)
  }
  p <- usc(combine_prefix(bframe))
  bsp <- paste0("bsp", p)
  pos <- grepl(paste0("^", bsp, "\\["), pars)
  newnames <- paste0("bsp", p, "_", spframe$coef)
  lc(out) <- rlist(pos, newnames)
  c(out) <- rename_prior(bsp, pars, names = spframe$coef)
  simo_coef <- get_simo_labels(spframe)
  for (i in seq_along(simo_coef)) {
    simo_old <- paste0("simo", p, "_", i)
    simo_new <- paste0("simo", p, "_", simo_coef[i])
    pos <- grepl(paste0("^", simo_old, "\\["), pars)
    simo_names <- paste0(simo_new, "[", seq_len(sum(pos)), "]")
    lc(out) <- rlist(pos, simo_names)
    c(out) <- rename_prior(
      simo_old, pars, new_class = simo_new, is_vector = TRUE
    )
  }
  if (has_special_prior(prior, bframe, class = "b")) {
    sdbsp <- paste0("sdbsp", p)
    pos <- grepl(paste0("^", sdbsp, "\\["), pars)
    sdbsp_names <- paste0(sdbsp, "_", spframe$coef)
    lc(out) <- rlist(pos, sdbsp_names)
  }
  out
}

# helps in renaming category specific effects parameters
rename_cs <- function(bframe, pars, ...) {
  stopifnot(is.bframel(bframe))
  out <- list()
  csef <- bframe$frame$cs$vars
  if (length(csef)) {
    p <- usc(combine_prefix(bframe))
    bcsp <- paste0("bcs", p)
    ncs <- length(csef)
    thres <- sum(grepl(paste0("^b", p, "_Intercept\\["), pars))
    csenames <- t(outer(csef, paste0("[", 1:thres, "]"), FUN = paste0))
    csenames <- paste0(bcsp, "_", csenames)
    sort_cse <- ulapply(seq_len(ncs), seq, to = thres * ncs, by = ncs)
    lc(out) <- rlist(
      grepl(paste0("^", bcsp, "\\["), pars), csenames, sort = sort_cse
    )
    c(out) <- rename_prior(bcsp, pars, names = csef)
  }
  out
}

# rename threshold parameters in ordinal models
rename_thres <- function(bframe, pars, ...) {
  out <- list()
  # renaming is only required if multiple threshold were estimated
  if (!has_thres_groups(bframe)) {
    return(out)
  }
  px <- check_prefix(bframe)
  p <- usc(combine_prefix(px))
  int <- paste0("b", p, "_Intercept")
  groups <- get_thres_groups(bframe)
  for (i in seq_along(groups)) {
    thres <- get_thres(bframe, groups[i])
    pos <- grepl(glue("^{int}_{i}\\["), pars)
    int_names <- glue("{int}[{groups[i]},{thres}]")
    lc(out) <- rlist(pos, int_names)
  }
  out
}

# rename baseline hazard parameters in cox models
rename_bhaz <- function(bframe, pars, ...) {
  out <- list()
  # renaming is only required if multiple threshold were estimated
  if (!has_bhaz_groups(bframe)) {
    return(out)
  }
  px <- check_prefix(bframe)
  p <- usc(combine_prefix(px))
  groups <- get_bhaz_groups(bframe)
  for (k in seq_along(groups)) {
    pos <- grepl(glue("^sbhaz{p}\\[{k},"), pars)
    funs <- seq_len(sum(pos))
    bhaz_names <- glue("sbhaz{p}[{groups[k]},{funs}]")
    lc(out) <- rlist(pos, bhaz_names)
  }
  out
}

# helps in renaming global noise free variables
# @param meframe data.frame returned by 'frame_me'
rename_Xme <- function(bframe, pars, ...) {
  meframe <- bframe$frame$me
  stopifnot(is.meframe(meframe))
  out <- list()
  levels <- attr(meframe, "levels")
  groups <- unique(meframe$grname)
  for (i in seq_along(groups)) {
    g <- groups[i]
    K <- which(meframe$grname %in% g)
    # rename mean and sd parameters
    for (par in c("meanme", "sdme")) {
      hpar <- paste0(par, "_", i)
      pos <- grepl(paste0("^", hpar, "\\["), pars)
      hpar_new <- paste0(par, "_", meframe$coef[K])
      lc(out) <- rlist(pos, hpar_new)
      c(out) <- rename_prior(hpar, pars, names = hpar_new)
    }
    # rename latent variable parameters
    for (k in K) {
      if (any(grepl("^Xme_", pars))) {
        Xme <- paste0("Xme_", k)
        pos <- grepl(paste0("^", Xme, "\\["), pars)
        Xme_new <- paste0("Xme_", meframe$coef[k])
        if (nzchar(g)) {
          indices <- gsub("[ \t\r\n]", ".", levels[[g]])
        } else {
          indices <- seq_len(sum(pos))
        }
        fnames <- paste0(Xme_new, "[", indices, "]")
        lc(out) <- rlist(pos, fnames)
      }
    }
    # rename correlation parameters
    if (meframe$cor[K[1]] && length(K) > 1L) {
      cor_type <- paste0("corme", usc(g))
      cor_names <- get_cornames(meframe$coef[K], cor_type, brackets = FALSE)
      cor_regex <- paste0("^corme_", i, "(\\[|$)")
      cor_pos <- grepl(cor_regex, pars)
      lc(out) <- rlist(cor_pos, cor_names)
      c(out) <- rename_prior(
        paste0("corme_", i), pars, new_class = paste0("corme", usc(g))
      )
    }
  }
  out
}

# helps in renaming estimated missing values
rename_Ymi <- function(bframe, pars, ...) {
  stopifnot(is.brmsframe(bframe))
  out <- list()
  if (is.formula(bframe$adforms$mi)) {
    resp <- usc(combine_prefix(bframe))
    Ymi <- paste0("Ymi", resp)
    pos <- grepl(paste0("^", Ymi, "\\["), pars)
    if (any(pos)) {
      Jmi <- bframe$frame$resp$Jmi
      fnames <- paste0(Ymi, "[", Jmi, "]")
      lc(out) <- rlist(pos, fnames)
    }
  }
  out
}

# helps in renaming parameters of gaussian processes
rename_gp <- function(bframe, pars, ...) {
  stopifnot(is.bframel(bframe))
  out <- list()
  p <- usc(combine_prefix(bframe), "prefix")
  gpframe <- bframe$frame$gp
  for (i in seq_rows(gpframe)) {
    # rename GP hyperparameters
    sfx1 <- gpframe$sfx1[[i]]
    sfx2 <- as.vector(gpframe$sfx2[[i]])
    sdgp <- paste0("sdgp", p)
    sdgp_old <- paste0(sdgp, "_", i)
    sdgp_pos <- grepl(paste0("^", sdgp_old, "\\["), pars)
    sdgp_names <- paste0(sdgp, "_", sfx1)
    lc(out) <- rlist(sdgp_pos, sdgp_names)
    c(out) <- rename_prior(sdgp_old, pars, names = sfx1, new_class = sdgp)

    lscale <- paste0("lscale", p)
    lscale_old <- paste0(lscale, "_", i)
    lscale_pos <- grepl(paste0("^", lscale_old, "\\["), pars)
    lscale_names <- paste0(lscale, "_", sfx2)
    lc(out) <- rlist(lscale_pos, lscale_names)
    c(out) <- rename_prior(lscale_old, pars, names = sfx2, new_class = lscale)

    zgp <- paste0("zgp", p)
    zgp_old <- paste0(zgp, "_", i)
    if (length(sfx1) > 1L) {
      # categorical 'by' variable
      for (j in seq_along(sfx1)) {
        zgp_old_sub <- paste0(zgp_old, "_", j)
        zgp_pos <- grepl(paste0("^", zgp_old_sub, "\\["), pars)
        if (any(zgp_pos)) {
          zgp_new <- paste0(zgp, "_", sfx1[j])
          fnames <- paste0(zgp_new, "[", seq_len(sum(zgp_pos)), "]")
          lc(out) <- rlist(zgp_pos, fnames)
        }
      }
    } else {
      zgp_pos <- grepl(paste0("^", zgp_old, "\\["), pars)
      if (any(zgp_pos)) {
        zgp_new <- paste0(zgp, "_", sfx1)
        fnames <- paste0(zgp_new, "[", seq_len(sum(zgp_pos)), "]")
        lc(out) <- rlist(zgp_pos, fnames)
      }
    }
  }
  out
}

# helps in renaming smoothing term parameters
rename_sm <- function(bframe, pars, prior, ...) {
  stopifnot(is.bframel(bframe))
  out <- list()
  smframe <- bframe$frame$sm
  if (!has_rows(smframe)) {
    return(out)
  }
  p <- usc(combine_prefix(bframe))
  Xs_names <- attr(smframe, "Xs_names")
  if (length(Xs_names)) {
    bs <- paste0("bs", p)
    pos <- grepl(paste0("^", bs, "\\["), pars)
    bsnames <- paste0(bs, "_", Xs_names)
    lc(out) <- rlist(pos, bsnames)
    c(out) <- rename_prior(bs, pars, names = Xs_names)
  }
  if (has_special_prior(prior, bframe, class = "b")) {
    sdbs <- paste0("sdbs", p)
    pos <- grepl(paste0("^", sdbs, "\\["), pars)
    sdbs_names <- paste0(sdbs, "_", Xs_names)
    lc(out) <- rlist(pos, sdbs_names)
  }

  sds <- paste0("sds", p)
  sds_names <- paste0(sds, "_", smframe$label)
  s <- paste0("s", p)
  snames <- paste0(s, "_", smframe$label)
  for (i in seq_rows(smframe)) {
    nbases <- smframe$nbases[i]
    sds_pos <- grepl(paste0("^", sds, "_", i), pars)
    sds_names_nb <- paste0(sds_names[i], "_", seq_len(nbases))
    lc(out) <- rlist(sds_pos, sds_names_nb)
    new_class <- paste0(sds, "_", smframe$label[i])
    c(out) <- rename_prior(paste0(sds, "_", i), pars, new_class = new_class)
    for (j in seq_len(nbases)) {
      spos <- grepl(paste0("^", s, "_", i, "_", j), pars)
      sfnames <- paste0(snames[i], "_", j, "[", seq_len(sum(spos)), "]")
      lc(out) <- rlist(spos, sfnames)
    }
  }
  out
}

# helps in renaming autocorrelation parameters
rename_ac <- function(bframe, pars, ...) {
  out <- list()
  acframe <- bframe$frame$ac
  stopifnot(is.acframe(acframe))
  resp <- usc(bframe$resp)
  if (has_ac_class(acframe, "unstr")) {
    times <- attr(acframe, "times")
    corname <- paste0("cortime", resp)
    regex <- paste0("^", corname, "\\[")
    cortime_names <- get_cornames(times, type = corname, brackets = FALSE)
    lc(out) <- rlist(grepl(regex, pars), cortime_names)
  }
  out
}

# helps in renaming group-level parameters
rename_re <- function(bframe, pars, ...) {
  out <- list()
  reframe <- bframe$frame$re
  if (!has_rows(reframe)) {
    return(out)
  }
  stopifnot(is.reframe(reframe))
  for (id in unique(reframe$id)) {
    r <- subset2(reframe, id = id)
    g <- r$group[1]
    rnames <- get_rnames(r)
    sd_names <- paste0("sd_", g, "__", as.vector(rnames))
    sd_pos <- grepl(paste0("^sd_", id, "(\\[|$)"), pars)
    lc(out) <- rlist(sd_pos, sd_names)
    c(out) <- rename_prior(
      paste0("sd_", id), pars, new_class = paste0("sd_", g),
      names = paste0("_", as.vector(rnames))
    )
    # rename group-level correlations
    if (nrow(r) > 1L && isTRUE(r$cor[1])) {
      type <- paste0("cor_", g)
      if (isTRUE(nzchar(r$by[1]))) {
        cor_names <- named_list(r$bylevels[[1]])
        for (j in seq_along(cor_names)) {
          cor_names[[j]] <- get_cornames(
            rnames[, j], type, brackets = FALSE
          )
        }
        cor_names <- unlist(cor_names)
      } else {
        cor_names <- get_cornames(rnames, type, brackets = FALSE)
      }
      cor_regex <- paste0("^cor_", id, "(_[[:digit:]]+)?(\\[|$)")
      cor_pos <- grepl(cor_regex, pars)
      lc(out) <- rlist(cor_pos, cor_names)
      c(out) <- rename_prior(
        paste0("cor_", id), pars, new_class = paste0("cor_", g)
      )
    }
  }
  if (any(grepl("^r_", pars))) {
    c(out) <- rename_re_levels(bframe, pars = pars)
  }
  reframe_t <- subset_reframe_dist(reframe, "student")
  for (i in seq_rows(reframe_t)) {
    df_pos <- grepl(paste0("^df_", reframe_t$ggn[i], "$"), pars)
    df_name <- paste0("df_", reframe_t$group[i])
    lc(out) <- rlist(df_pos, df_name)
  }
  out
}

# helps in renaming varying effects parameters per level
rename_re_levels <- function(bframe, pars, ...)  {
  out <- list()
  reframe <- bframe$frame$re
  stopifnot(is.reframe(reframe))
  for (i in seq_rows(reframe)) {
    r <- reframe[i, ]
    p <- usc(combine_prefix(r))
    r_parnames <- paste0("r_", r$id, p, "_", r$cn)
    r_regex <- paste0("^", r_parnames, "(\\[|$)")
    r_new_parname <- paste0("r_", r$group, usc(p))
    # rstan doesn't like whitespaces in parameter names
    levels <- gsub("[ \t\r\n]", ".", attr(reframe, "levels")[[r$group]])
    index_names <- make_index_names(levels, r$coef, dim = 2)
    fnames <- paste0(r_new_parname, index_names)
    lc(out) <- rlist(grepl(r_regex, pars), fnames)
  }
  out
}

# helps to rename correlation parameters of likelihoods
rename_family_cor_pars <- function(x, pars, ...) {
  stopifnot(is.brmsterms(x))
  out <- list()
  if (is_logistic_normal(x$family)) {
    predcats <- get_predcats(x$family)
    lncor_names <- get_cornames(
      predcats, type = "lncor", brackets = FALSE
    )
    lc(out) <- rlist(grepl("^lncor\\[", pars), lncor_names)
  }
  out
}

# helps in renaming prior parameters
# @param class the class of the parameters
# @param pars names of all parameters in the model
# @param names names to replace digits at the end of parameter names
# @param new_class optional replacement of the orginal class name
# @param is_vector indicate if the prior parameter is a vector
rename_prior <- function(class, pars, names = NULL, new_class = class,
                         is_vector = FALSE) {
  out <- list()
  # 'stan_rngprior' adds '__' before the digits to disambiguate
  regex <- paste0("^prior_", class, "(__[[:digit:]]+|$|\\[)")
  pos_priors <- which(grepl(regex, pars))
  if (length(pos_priors)) {
    priors <- gsub(
      paste0("^prior_", class),
      paste0("prior_", new_class),
      pars[pos_priors]
    )
    if (is_vector) {
      if (!is.null(names)) {
        .names <- paste0("_", names)
        for (i in seq_along(priors)) {
          priors[i] <- gsub("\\[[[:digit:]]+\\]$", .names[i], priors[i])
        }
      }
      lc(out) <- rlist(pos_priors, priors)
    } else {
      digits <- sapply(priors, function(prior) {
        d <- regmatches(prior, gregexpr("__[[:digit:]]+$", prior))[[1]]
        if (length(d)) as.numeric(substr(d, 3, nchar(d))) else 0
      })
      for (i in seq_along(priors)) {
        if (digits[i] && !is.null(names)) {
          priors[i] <- gsub("_[[:digit:]]+$", names[digits[i]], priors[i])
        }
        if (pars[pos_priors[i]] != priors[i]) {
          lc(out) <- rlist(pos_priors[i], priors[i])
        }
      }
    }
  }
  out
}

# helper for rename_* functions
rlist <- function(pos, fnames, ...) {
  structure(nlist(pos, fnames, ...), class = c("rlist", "list"))
}

is.rlist <- function(x) {
  inherits(x, "rlist")
}

# compute index names in square brackets for indexing stan parameters
# @param rownames a vector of row names
# @param colnames a vector of columns
# @param dim the number of output dimensions
# @return all index pairs of rows and cols
make_index_names <- function(rownames, colnames = NULL, dim = 1) {
  if (!dim %in% c(1, 2))
    stop("dim must be 1 or 2")
  if (dim == 1) {
    index_names <- paste0("[", rownames, "]")
  } else {
    tmp <- outer(rownames, colnames, FUN = paste, sep = ",")
    index_names <- paste0("[", tmp, "]")
  }
  index_names
}

# save original order of the parameters in the stanfit object
save_old_par_order <- function(x, x2 = NULL) {
  stopifnot(is.brmsfit(x))
  if (is.null(x2)) {
    # used in rename_pars() to store the old order
    x$fit@sim$pars_oi_old <- x$fit@sim$pars_oi
    x$fit@sim$dims_oi_old <- x$fit@sim$dims_oi
    x$fit@sim$fnames_oi_old <- x$fit@sim$fnames_oi
  } else {
    # used in combine_models() to take the old order from another model
    stopifnot(is.brmsfit(x2))
    x$fit@sim$pars_oi_old <- x2$fit@sim$pars_oi_old
    x$fit@sim$dims_oi_old <- x2$fit@sim$dims_oi_old
    x$fit@sim$fnames_oi_old <- x2$fit@sim$fnames_oi_old
  }
  x
}

# perform actual renaming of Stan parameters
# @param x a brmsfit object
# @param y a list of lists each element allowing
#   to rename certain parameters
# @return a brmsfit object with updated parameter names
do_renaming <- function(x, y) {
  .do_renaming <- function(x, y) {
    stopifnot(is.rlist(y))
    x$fit@sim$fnames_oi[y$pos] <- y$fnames
    for (i in seq_len(chains)) {
      names(x$fit@sim$samples[[i]])[y$pos] <- y$fnames
      if (!is.null(y$sort)) {
        x$fit@sim$samples[[i]][y$pos] <-
          x$fit@sim$samples[[i]][y$pos][y$sort]
      }
    }
    return(x)
  }
  chains <- length(x$fit@sim$samples)
  for (i in seq_along(y)) {
    x <- .do_renaming(x, y[[i]])
  }
  x
}

# order parameter draws after parameter class
# @param x brmsfit object
reorder_pars <- function(x) {
  all_classes <- unique(c(
    "b", "bs", "bsp", "bcs", "ar", "ma", "sderr", "lagsar", "errorsar", "car",
    "rhocar", "sdcar", "cosy", "cortime", "sd", "cor", "df", "sds", "sdgp",
    "lscale", valid_dpars(x), "hs", "R2D2", "sdb", "sdbsp", "sdbs", "sdar",
    "sdma", "lncor", "Intercept", "tmp", "rescor", "delta", "simo", "r", "s",
    "zgp", "rcar", "sbhaz", "Ymi", "Yl", "meanme", "sdme", "corme", "Xme",
    "prior", "lprior", "lp"
  ))
  # reorder parameter classes
  class <- get_matches("^[^_]+", x$fit@sim$pars_oi)
  new_order <- order(
    factor(class, levels = all_classes),
    !grepl("_Intercept(_[[:digit:]]+)?$", x$fit@sim$pars_oi)
  )
  x$fit@sim$dims_oi <- x$fit@sim$dims_oi[new_order]
  x$fit@sim$pars_oi <- names(x$fit@sim$dims_oi)
  # reorder single parameter names
  nsubpars <- ulapply(x$fit@sim$dims_oi, prod)
  has_subpars <- nsubpars > 0
  new_order <- new_order[has_subpars]
  nsubpars <- nsubpars[has_subpars]
  num <- lapply(seq_along(new_order), function(x)
    as.numeric(paste0(x, ".", sprintf("%010d", seq_len(nsubpars[x]))))
  )
  new_order <- order(unlist(num[order(new_order)]))
  x$fit@sim$fnames_oi <- x$fit@sim$fnames_oi[new_order]
  chains <- length(x$fit@sim$samples)
  for (i in seq_len(chains)) {
    # attributes of samples must be kept
    x$fit@sim$samples[[i]] <-
      subset_keep_attr(x$fit@sim$samples[[i]], new_order)
  }
  x
}

# wrapper function to compute and store quantities in the stanfit
# object which were not computed / stored by Stan itself
# @param x a brmsfit object
# @return a brmsfit object
compute_quantities <- function(x) {
  stopifnot(is.brmsfit(x))
  x <- compute_xi(x)
  x
}

# helper function to compute parameter xi, which is currently
# defined in the Stan model block and thus not being stored
# @param x a brmsfit object
# @return a brmsfit object
compute_xi <- function(x, ...) {
  UseMethod("compute_xi")
}

#' @export
compute_xi.brmsfit <- function(x, ...) {
  if (!any(grepl("^tmp_xi(_|$)", variables(x)))) {
    return(x)
  }
  prep <- try(prepare_predictions(x))
  if (is_try_error(prep)) {
    warning2("Trying to compute 'xi' was unsuccessful. ",
             "Some S3 methods may not work as expected.")
    return(x)
  }
  compute_xi(prep, fit = x, ...)
}

#' @export
compute_xi.mvbrmsprep <- function(x, fit, ...) {
  stopifnot(is.brmsfit(fit))
  for (resp in names(x$resps)) {
    fit <- compute_xi(x$resps[[resp]], fit = fit, ...)
  }
  fit
}

#' @export
compute_xi.brmsprep <- function(x, fit, ...) {
  stopifnot(is.brmsfit(fit))
  resp <- usc(x$resp)
  tmp_xi_name <- paste0("tmp_xi", resp)
  if (!tmp_xi_name %in% variables(fit)) {
    return(fit)
  }
  mu <- get_dpar(x, "mu")
  sigma <- get_dpar(x, "sigma")
  y <- matrix(x$data$Y, dim(mu)[1], dim(mu)[2], byrow = TRUE)
  bs <- -1 / matrixStats::rowRanges((y - mu) / sigma)
  bs <- matrixStats::rowRanges(bs)
  tmp_xi <- as.vector(as.matrix(fit, variable = tmp_xi_name))
  xi <- inv_logit(tmp_xi) * (bs[, 2] - bs[, 1]) + bs[, 1]
  # write xi into stanfit object
  xi_name <- paste0("xi", resp)
  samp_chain <- length(xi) / fit$fit@sim$chains
  for (i in seq_len(fit$fit@sim$chains)) {
    xi_part <- xi[((i - 1) * samp_chain + 1):(i * samp_chain)]
    # add warmup draws not used anyway
    xi_part <- c(rep(0, fit$fit@sim$warmup2[1]), xi_part)
    fit$fit@sim$samples[[i]][[xi_name]] <- xi_part
  }
  fit$fit@sim$pars_oi <- c(fit$fit@sim$pars_oi, xi_name)
  fit$fit@sim$dims_oi[[xi_name]] <- numeric(0)
  fit$fit@sim$fnames_oi <- c(fit$fit@sim$fnames_oi, xi_name)
  fit$fit@sim$n_flatnames <- fit$fit@sim$n_flatnames + 1
  fit
}
