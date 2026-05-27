# build_registry.R
#
# Scans Code/*.Rmd and writes Code/REGISTRY.md as a readable, per-script view
# with Processed-Data dependency tracking.
#
# Usage (from project root):
#   Rscript "Code/_Claude Scripts/build_registry.R"
#
# .Rmd convention: YAML front-matter includes a top-level `registry:` block:
#   ---
#   title: "..."
#   registry:
#     purpose: "..."
#     inputs:   [...]
#     outputs:  [...]
#     paper_target: "..."
#     notes: "..."
#   ---
#
# script_id is inferred from filename prefix (e.g. `3. Claude_Foo.Rmd` -> 3),
# or `12b. Claude_Foo.Rmd` -> 12b. Explicit `script_id:` in YAML overrides.
#
# Scripts outside Code/*.Rmd are NOT tracked — working scripts in
# Code/_Claude Scripts/ are managed via session logs and Claude's memory.

suppressPackageStartupMessages({
  library(yaml)
  library(data.table)
})

SCAN_DIR  <- "Code"
OUT_FILE  <- "Code/REGISTRY.md"

# Auto-detect paper directory: look for a directory under Paper/ that contains
# .tex files, or fall back to "Paper/" itself.
detect_paper_dir <- function() {
  candidates <- c(
    list.dirs("Paper", recursive = TRUE, full.names = TRUE),
    list.dirs(".", recursive = FALSE, full.names = TRUE)
  )
  candidates <- unique(candidates)
  for (d in candidates) {
    tex_files <- list.files(d, pattern = "\\.tex$", full.names = TRUE)
    if (length(tex_files) > 0 && grepl("^(\\.[\\/])?Paper", d)) return(d)
  }
  # Check for Paper Github/ pattern (common for GitHub-Overleaf linked repos)
  gh_dirs <- list.dirs(".", recursive = TRUE, full.names = TRUE)
  gh_dirs <- gh_dirs[grepl("Paper.*Github", gh_dirs, ignore.case = TRUE)]
  for (d in gh_dirs) {
    tex_files <- list.files(d, pattern = "\\.tex$", full.names = TRUE, recursive = TRUE)
    if (length(tex_files) > 0) return(d)
  }
  "Paper"
}

PAPER_DIR <- detect_paper_dir()

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ---- YAML extraction -------------------------------------------------------

extract_rmd_registry <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  bounds <- which(trimws(lines) == "---")
  if (length(bounds) < 2) return(NULL)
  yaml_text <- paste(lines[(bounds[1] + 1):(bounds[2] - 1)], collapse = "\n")
  parsed <- tryCatch(yaml::yaml.load(yaml_text), error = function(e) NULL)
  parsed$registry
}

parse_id <- function(source) {
  m <- regmatches(source, regexpr("^\\d+[a-z]?", source))
  if (length(m) == 0) {
    return(list(num = NA_integer_, suffix = "", display = NA_character_))
  }
  num <- as.integer(regmatches(m, regexpr("^\\d+", m)))
  sfx <- regmatches(m, regexpr("[a-z]$", m))
  sfx <- if (length(sfx) > 0) sfx else ""
  list(num = num, suffix = sfx, display = m)
}

# ---- Scan ------------------------------------------------------------------

scan_scripts <- function() {
  files <- list.files(SCAN_DIR, pattern = "\\.Rmd$", full.names = TRUE,
                      ignore.case = TRUE, recursive = FALSE)
  rows <- list()
  for (f in files) {
    reg <- extract_rmd_registry(f)
    fi  <- file.info(f)
    rel <- sub("^\\./", "", gsub("\\\\", "/", f))
    pid <- if (!is.null(reg$script_id)) parse_id(as.character(reg$script_id))
           else parse_id(basename(f))
    rows[[length(rows) + 1]] <- list(
      path          = rel,
      basename      = basename(f),
      script_id     = pid$display,
      id_num        = pid$num,
      id_suffix     = pid$suffix,
      purpose       = reg$purpose      %||% "",
      inputs        = list(reg$inputs  %||% character(0)),
      outputs       = list(reg$outputs %||% character(0)),
      paper_target  = reg$paper_target %||% "",
      notes         = reg$notes        %||% "",
      last_modified = format(fi$mtime, "%Y-%m-%d"),
      has_registry  = !is.null(reg)
    )
  }
  rbindlist(rows, fill = TRUE)
}

# ---- Drift detection (YAML vs actual file I/O in code) --------------------

strip_inline_comment <- function(line) {
  pos <- regexpr("#", line, fixed = TRUE)
  if (pos == -1) return(line)
  before <- substr(line, 1, pos - 1)
  q <- nchar(gsub('[^"]', "", gsub('\\\\"', "", before)))
  if (q %% 2 == 1) return(line)
  substr(line, 1, pos - 1)
}

paren_balance <- function(line) {
  safe <- gsub('"[^"]*"', '""', line)
  sum(strsplit(safe, "")[[1]] == "(") - sum(strsplit(safe, "")[[1]] == ")")
}

join_logical_lines <- function(lines) {
  out <- character(0); buf <- character(0); depth <- 0
  for (ln in lines) {
    s <- strip_inline_comment(ln)
    if (length(buf) == 0 && nchar(trimws(s)) == 0) next
    buf <- c(buf, s)
    depth <- depth + paren_balance(s)
    if (depth <= 0) {
      joined <- paste(trimws(buf), collapse = " ")
      if (nchar(trimws(joined)) > 0) out <- c(out, joined)
      buf <- character(0); depth <- 0
    }
  }
  if (length(buf) > 0) {
    joined <- paste(trimws(buf), collapse = " ")
    if (nchar(trimws(joined)) > 0) out <- c(out, joined)
  }
  out
}

split_top_level <- function(s) {
  depth <- 0; in_str <- FALSE; parts <- character(0); buf <- ""
  for (i in seq_len(nchar(s))) {
    ch <- substr(s, i, i)
    if (!in_str) {
      if      (ch == '"') in_str <- TRUE
      else if (ch == "(") depth <- depth + 1
      else if (ch == ")") depth <- depth - 1
      else if (ch == "," && depth == 0) {
        parts <- c(parts, buf); buf <- ""; next
      }
    } else if (ch == '"') in_str <- FALSE
    buf <- paste0(buf, ch)
  }
  if (nchar(trimws(buf)) > 0) parts <- c(parts, buf)
  trimws(parts)
}

extract_parens <- function(s, open_pos) {
  if (substr(s, open_pos, open_pos) != "(") return(NULL)
  depth <- 1; in_str <- FALSE; i <- open_pos + 1; start <- i
  while (i <= nchar(s) && depth > 0) {
    ch <- substr(s, i, i)
    if (!in_str) {
      if      (ch == '"') in_str <- TRUE
      else if (ch == "(") depth <- depth + 1
      else if (ch == ")") { depth <- depth - 1; if (depth == 0) return(substr(s, start, i - 1)) }
    } else if (ch == '"') in_str <- FALSE
    i <- i + 1
  }
  NULL
}

resolve_expr <- function(expr, dict, depth = 0) {
  if (depth > 8) return(NA_character_)
  expr <- trimws(expr)
  m <- regmatches(expr, regexec("^(?:file|filename|sink|con|path)\\s*=\\s*(.+)$", expr, perl = TRUE))[[1]]
  if (length(m) == 2) expr <- trimws(m[2])

  if (grepl('^"[^"]*"$', expr)) return(sub('^"(.*)"$', "\\1", expr))
  if (grepl("^[A-Za-z_][A-Za-z0-9_.]*$", expr, perl = TRUE)) {
    return(if (!is.null(dict[[expr]])) dict[[expr]] else NA_character_)
  }
  if (grepl("^file\\.path\\s*\\(", expr, perl = TRUE)) {
    open_pos <- regexpr("\\(", expr)[1]
    inner <- extract_parens(expr, open_pos)
    if (is.null(inner)) return(NA_character_)
    args <- split_top_level(inner)
    parts <- character(0)
    for (a in args) {
      r <- resolve_expr(a, dict, depth + 1)
      if (is.na(r)) return(NA_character_)
      parts <- c(parts, r)
    }
    return(paste(parts, collapse = "/"))
  }
  NA_character_
}

build_path_dict <- function(logical_lines) {
  dict <- list()
  for (ln in logical_lines) {
    m <- regmatches(ln, regexec("^\\s*([A-Za-z_][A-Za-z0-9_.]*)\\s*<-\\s*(.+?)\\s*$", ln, perl = TRUE))[[1]]
    if (length(m) != 3) next
    var <- m[2]; rhs <- m[3]
    r <- resolve_expr(rhs, dict)
    if (!is.na(r)) dict[[var]] <- r
  }
  dict
}

find_io <- function(ln, dict) {
  reads <- character(0); writes <- character(0)

  read_fns <- c("fread", "read_parquet", "read\\.csv", "read_csv", "readRDS",
                "ReadableFile\\$create", "open_dataset", "arrow::read_parquet")
  write_2 <- c("fwrite", "write\\.csv", "write_parquet", "arrow::write_parquet",
               "saveRDS", "save_kable")

  scan <- function(fn_pat, arg_idx_or_named) {
    starts <- gregexpr(sprintf("(?<![A-Za-z0-9_.])%s\\s*\\(", fn_pat), ln, perl = TRUE)[[1]]
    if (starts[1] == -1) return(character(0))
    out <- character(0)
    for (k in seq_along(starts)) {
      start <- starts[k]
      mlen  <- attr(starts, "match.length")[k]
      paren_at <- start + mlen - 1
      body <- extract_parens(ln, paren_at)
      if (is.null(body)) next
      args <- split_top_level(body)
      chosen <- NULL
      for (a in args) {
        mm <- regmatches(a, regexec("^(?:file|filename|sink|path)\\s*=\\s*(.+)$", a, perl = TRUE))[[1]]
        if (length(mm) == 2) { chosen <- mm[2]; break }
      }
      if (is.null(chosen) && is.numeric(arg_idx_or_named)) {
        if (length(args) >= arg_idx_or_named) {
          cand <- args[arg_idx_or_named]
          if (!grepl("^[A-Za-z_][A-Za-z0-9_.]*\\s*=[^=]", cand, perl = TRUE)) chosen <- cand
        }
      }
      if (!is.null(chosen)) {
        r <- resolve_expr(chosen, dict)
        if (!is.na(r)) out <- c(out, r)
      }
    }
    out
  }

  for (fn in read_fns) reads  <- c(reads,  scan(fn, 1))
  for (fn in write_2)  writes <- c(writes, scan(fn, 2))
  writes <- c(writes, scan("ggsave", 1))
  writes <- c(writes, scan("etable", NA))

  list(reads = unique(reads), writes = unique(writes))
}

normalize_rel <- function(path, project_dir) {
  if (is.null(project_dir) || is.na(project_dir) || nchar(project_dir) == 0) return(path)
  pd <- gsub("\\\\", "/", project_dir)
  p  <- gsub("\\\\", "/", path)
  if (startsWith(p, paste0(pd, "/"))) return(substr(p, nchar(pd) + 2, nchar(p)))
  p
}

detect_drift <- function(script_path, declared_inputs, declared_outputs) {
  lines   <- readLines(script_path, warn = FALSE, encoding = "UTF-8")
  logical <- join_logical_lines(lines)
  dict    <- build_path_dict(logical)
  pd      <- dict[["project_dir"]]

  reads <- character(0); writes <- character(0)
  for (ln in logical) {
    io <- find_io(ln, dict)
    reads  <- c(reads,  io$reads)
    writes <- c(writes, io$writes)
  }

  reads  <- unique(vapply(reads,  normalize_rel, character(1), project_dir = pd))
  writes <- unique(vapply(writes, normalize_rel, character(1), project_dir = pd))

  is_rel <- function(x) !grepl("^(?:[A-Za-z]:|/|~)", x, perl = TRUE)
  reads  <- reads[is_rel(reads)]
  writes <- writes[is_rel(writes)]

  list(
    undeclared_inputs  = setdiff(reads,  declared_inputs),
    undeclared_outputs = setdiff(writes, declared_outputs),
    unused_inputs      = setdiff(declared_inputs,  reads),
    unused_outputs     = setdiff(declared_outputs, writes)
  )
}

# ---- Paper verification ----------------------------------------------------

load_paper_content <- function() {
  if (!dir.exists(PAPER_DIR)) return("")
  tex <- list.files(PAPER_DIR, pattern = "\\.tex$", recursive = TRUE,
                    full.names = TRUE)
  if (length(tex) == 0) return("")
  paste(vapply(tex, function(f)
    paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    character(1)), collapse = "\n\n")
}

check_in_paper <- function(outputs, paper_text) {
  if (length(outputs) == 0 || nchar(paper_text) == 0) return("no")
  stems <- tools::file_path_sans_ext(basename(outputs))
  stems <- stems[nchar(stems) > 3]
  if (length(stems) == 0) return("no")
  if (any(vapply(stems, function(s) grepl(s, paper_text, fixed = TRUE),
                 logical(1)))) "yes" else "no"
}

# ---- Output categorization -------------------------------------------------

categorize_paths <- function(paths, prefix) {
  if (length(paths) == 0) return(character(0))
  paths[startsWith(paths, prefix)]
}

categorize_outputs <- function(outputs) {
  list(
    figures   = categorize_paths(outputs, "Output/Figures/"),
    tables    = categorize_paths(outputs, "Output/Tables/"),
    processed = categorize_paths(outputs, "Output/Processed Data/"),
    other     = setdiff(outputs,
                        c(categorize_paths(outputs, "Output/Figures/"),
                          categorize_paths(outputs, "Output/Tables/"),
                          categorize_paths(outputs, "Output/Processed Data/")))
  )
}

# ---- Markdown rendering ----------------------------------------------------

fmt_paths <- function(paths, indent = "  ") {
  if (length(paths) == 0) return(paste0(indent, "- _(none)_"))
  paste0(indent, "- `", paths, "`", collapse = "\n")
}

render_script <- function(r, in_paper) {
  outs <- categorize_outputs(r$outputs[[1]])
  header_id <- if (is.na(r$script_id) || r$script_id == "")
                 r$basename
               else
                 sprintf("%s — `%s`", r$script_id, r$basename)

  lines <- c(sprintf("## %s", header_id), "")

  if (!r$has_registry) {
    lines <- c(lines,
               "_(no `registry:` YAML block — add one)_",
               "",
               sprintf("- **Last modified**: %s", r$last_modified),
               "",
               "---", "")
    return(lines)
  }

  lines <- c(lines,
    sprintf("- **Purpose**: %s", r$purpose),
    sprintf("- **Paper target**: %s",
            if (nchar(r$paper_target) == 0) "_(none)_" else r$paper_target),
    sprintf("- **In paper**: %s", in_paper),
    sprintf("- **Last modified**: %s", r$last_modified),
    "- **Inputs**:",
    fmt_paths(r$inputs[[1]]),
    "- **Outputs — Figures**:",
    fmt_paths(outs$figures),
    "- **Outputs — Tables**:",
    fmt_paths(outs$tables),
    "- **Outputs — Processed Data**:",
    fmt_paths(outs$processed)
  )

  if (length(outs$other) > 0) {
    lines <- c(lines,
               "- **Outputs — Other** _(not in Output/Figures, Output/Tables, or Output/Processed Data)_:",
               fmt_paths(outs$other))
  }

  if (nchar(r$notes) > 0) {
    lines <- c(lines, sprintf("- **Notes**: %s", r$notes))
  }

  lines <- c(lines, "", "---", "")
  lines
}

render_processed_graph <- function(dt) {
  writes <- list(); reads <- list()
  for (i in seq_len(nrow(dt))) {
    id <- if (is.na(dt$script_id[i]) || dt$script_id[i] == "")
            dt$basename[i] else dt$script_id[i]
    for (o in categorize_paths(dt$outputs[[i]], "Output/Processed Data/")) {
      writes[[length(writes) + 1]] <- list(file = o, scr = id)
    }
    for (p in categorize_paths(dt$inputs[[i]], "Output/Processed Data/")) {
      reads[[length(reads) + 1]] <- list(file = p, scr = id)
    }
  }

  all_files <- sort(unique(c(
    vapply(writes, `[[`, character(1), "file"),
    vapply(reads,  `[[`, character(1), "file")
  )))

  lines <- c("## Processed Data — Dependency Graph", "",
             "_Each intermediate file with its producer and downstream consumers._",
             "")

  if (length(all_files) == 0) {
    lines <- c(lines, "_(no processed-data files registered)_", "")
    return(lines)
  }

  for (f in all_files) {
    ws <- sort(unique(unlist(lapply(writes, function(x) if (x$file == f) x$scr else NULL))))
    rs <- sort(unique(unlist(lapply(reads,  function(x) if (x$file == f) x$scr else NULL))))
    lines <- c(lines,
      sprintf("### `%s`", f),
      sprintf("- **Produced by**: %s",
              if (length(ws) == 0) "_(not a registered script — likely a helper in `_Claude Scripts/`)_"
              else paste(ws, collapse = ", ")),
      sprintf("- **Consumed by**: %s",
              if (length(rs) == 0) "_(no registered consumers)_"
              else paste(rs, collapse = ", ")),
      "")
  }
  lines
}

render_drift_warnings <- function(dt) {
  lines <- c("---", "",
             "## Drift Warnings",
             "",
             "_Mismatches between the `registry:` YAML and the file-I/O calls detected in code._",
             "_The builder does NOT auto-edit YAML — fix discrepancies manually and rerun._",
             "")
  any_drift <- FALSE
  for (i in seq_len(nrow(dt))) {
    if (!dt$has_registry[i]) next
    d <- detect_drift(dt$path[i], dt$inputs[[i]], dt$outputs[[i]])
    if (length(d$undeclared_inputs) == 0 &&
        length(d$undeclared_outputs) == 0 &&
        length(d$unused_inputs) == 0 &&
        length(d$unused_outputs) == 0) next
    any_drift <- TRUE
    hdr <- if (is.na(dt$script_id[i]) || dt$script_id[i] == "")
             dt$basename[i]
           else
             sprintf("%s — `%s`", dt$script_id[i], dt$basename[i])
    lines <- c(lines, sprintf("### %s", hdr), "")
    if (length(d$undeclared_inputs) > 0) {
      lines <- c(lines, "- **Read in code but missing from `inputs:`**:",
                 paste0("  - `", d$undeclared_inputs, "`"))
    }
    if (length(d$undeclared_outputs) > 0) {
      lines <- c(lines, "- **Written in code but missing from `outputs:`**:",
                 paste0("  - `", d$undeclared_outputs, "`"))
    }
    if (length(d$unused_inputs) > 0) {
      lines <- c(lines, "- **Declared in `inputs:` but no read detected** _(possibly stale, or a call pattern the builder doesn't recognize)_:",
                 paste0("  - `", d$unused_inputs, "`"))
    }
    if (length(d$unused_outputs) > 0) {
      lines <- c(lines, "- **Declared in `outputs:` but no write detected** _(possibly stale, or a call pattern the builder doesn't recognize)_:",
                 paste0("  - `", d$unused_outputs, "`"))
    }
    lines <- c(lines, "")
  }
  if (!any_drift) {
    lines <- c(lines, "_No drift detected across any script — YAML and code are in sync._", "")
  }
  lines
}

write_registry <- function(dt, paper_text) {
  dt[, in_paper := vapply(outputs, check_in_paper,
                          paper_text = paper_text, character(1))]
  setorderv(dt, c("id_num", "id_suffix", "path"), na.last = TRUE)

  lines <- c(
    "# Script Registry",
    "",
    sprintf("_Auto-generated by `Code/_Claude Scripts/build_registry.R` on %s._",
            Sys.Date()),
    "_Do not edit by hand — edit the `registry:` YAML block in each script, then re-run the builder._",
    "",
    sprintf("Tracks `.Rmd` scripts in `Code/`. %d registered, %d missing metadata.",
            sum(dt$has_registry), sum(!dt$has_registry)),
    "",
    "---",
    ""
  )

  for (i in seq_len(nrow(dt))) {
    lines <- c(lines, render_script(dt[i], dt$in_paper[i]))
  }

  lines <- c(lines, render_processed_graph(dt))
  lines <- c(lines, render_drift_warnings(dt))

  missing <- dt[has_registry == FALSE]
  if (nrow(missing) > 0) {
    lines <- c(lines, "---", "", "## Scripts Without Registry Metadata", "")
    for (p in missing$basename) {
      lines <- c(lines, sprintf("- `%s`", p))
    }
    lines <- c(lines, "")
  }

  writeLines(lines, OUT_FILE, useBytes = TRUE)
  cat(sprintf(
    "Registry updated: %d scripts (%d with metadata, %d missing) -> %s\n",
    nrow(dt), sum(dt$has_registry), sum(!dt$has_registry), OUT_FILE))
}

# ---- Main ------------------------------------------------------------------

main <- function() {
  dt <- scan_scripts()
  if (nrow(dt) == 0) {
    cat("No .Rmd scripts found in Code/.\n")
    return(invisible())
  }
  write_registry(dt, load_paper_content())
}

main()
