---
paths:
  - "Output/**"
---

# Output Conventions

## Output Destinations

| Output type       | Location                    | Format               |
|-------------------|-----------------------------|----------------------|
| Tables            | `Output/Tables/`            | LaTeX (`.tex`), CSV  |
| Figures           | `Output/Figures/`           | PDF preferred, PNG   |
| Processed data    | `Output/Processed Data/`    | Parquet, CSV, RDS    |
| Scripts           | `Code/`                     | `Claude_XXXX.Rmd`    |
| Purled scripts    | `Code/_Claude Scripts/`     | `Claude_XXXX.R`      |
| Session logs      | `Code/_Claude Logs/`        | Markdown (`.md`)     |

## Destination Rules

Choose the destination by output purpose:

- **`Output/Figures/`** — any `.pdf`, `.png`, or `.jpg` figure.
- **`Output/Tables/`** — **terminal** paper tables: LaTeX `.tex` files and CSVs that feed the paper narrative directly and are **not consumed by any other script**.
- **`Output/Processed Data/`** — **intermediate** artifacts: outputs of one script that are then **inputs to another** `.Rmd` (or to a helper `.R`). Use `proc_dir <- file.path(project_dir, "Output/Processed Data")` as the path variable.

**Rule of thumb:** if any other script reads the file, put it in `Output/Processed Data/`. Otherwise `Output/Tables/` (for tabular) or `Output/Figures/` (for graphical).

## Naming

- Figures: descriptive names matching the paper reference (e.g., `Figure_1_TimeSeries.pdf`).
- Tables: descriptive names matching the paper reference (e.g., `Table_1_SummaryStats.tex`).
- Processed data: descriptive names indicating content (e.g., `panel_monthly_estimates.parquet`).
- All superseded outputs go to the `_Archive/` subfolder within their directory.
