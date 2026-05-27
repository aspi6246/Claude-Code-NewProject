---
paths:
  - "**/*.R"
  - "**/*.Rmd"
  - "Code/**"
  - "Data/**"
---

# R & Data Analysis Conventions

## Language and Style

- All code is written in **R**, primarily using **R Markdown (`.Rmd`)** files.
- Key libraries: `fixest`, `arrow`, `dplyr`. Prefer these over alternatives (e.g., prefer `dplyr` over `data.table` for data manipulation unless data size calls for `data.table`; `fixest` over `lm`/`felm` for regressions).
- Use `arrow::read_parquet()` or `arrow::open_dataset()` for large datasets. Avoid reading entire large files into memory when a filtered query will do.

## File Naming and Locations

- **Canonical scripts** live in `Code/` and are named with a numbered prefix indicating pipeline order: `01_clean_data.Rmd`, `02_summary_stats.Rmd`, `03_main_estimation.Rmd`, etc.
- **Claude-created scripts** also live in `Code/` and are named `Claude_XXXX.Rmd` (e.g., `Claude_summary_stats.Rmd`). For multi-author projects, use `Claude_<Author>_XXXX.Rmd`.
- **Purled `.R` copies** of Claude scripts go in `Code/_Claude Scripts/`. These are working copies for non-interactive execution; the `.Rmd` in `Code/` is always the canonical source.
- **Superseded scripts** get moved to the relevant `_Archive/` subfolder, never deleted.

## Pipeline Order

Scripts are numbered to indicate execution order:

```
01_XXXX.Rmd  ->  reads Raw data, writes to Data/Processed/
02_XXXX.Rmd  ->  reads Processed data, produces summary stats
03_XXXX.Rmd  ->  main estimation
...
```

If Claude creates a new script, AUTHOR_NAME will assign its number and position in the pipeline. Claude should ask where it fits rather than assuming.

## Data Handling

- **`Data/Raw/`** is read-only. Original source data lives here and is never modified.
- **`Data/Processed/`** holds all transformed, merged, or constructed datasets.
- When working with large Parquet files, prefer `arrow::open_dataset()` with filtered queries over loading entire datasets into memory.
- Always document in the script header which raw files are read and which processed files are produced.

## Script Registry

Each paper-producing `Code/*.Rmd` script should carry a `registry:` YAML block in its front-matter:

```yaml
---
title: "Descriptive Title"
author: "AUTHOR_NAME"
output: html_document
registry:
  purpose: "Brief description of what this script does"
  inputs:
    - Data/Processed/input_file.parquet
  outputs:
    - Output/Figures/figure_name.pdf
    - Output/Tables/table_name.tex
  paper_target: "Table 1, Figure 3"
  notes: "Any caveats or memory requirements"
---
```

After creating or editing a `Code/*.Rmd`, update its `registry:` block and run:
```bash
Rscript "Code/_Claude Scripts/build_registry.R"
```
