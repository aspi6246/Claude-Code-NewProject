---
paths:
  - "**/*.tex"
  - "**/*.bib"
  - "Paper/**"
---

# Paper Editing Conventions

## General Rules

- The paper is written in **LaTeX** and lives in `Paper/`.
- Keep edits minimal and localised. Flag what was changed so AUTHOR_NAME can review.
- BibTeX references go in the existing `.bib` file. Do not create a new one.
- Do not reformat or restructure sections without asking.

## Git Workflow (if Paper is linked to GitHub/Overleaf)

If `Paper/` is a Git clone linked to GitHub and Overleaf:

1. Edit `.tex` files in `Paper/`.
2. `git add` + `git commit` + `git push` to GitHub.
3. Changes automatically sync to Overleaf.
4. Push after completing each distinct task or edit.
5. Push before ending a session.
6. Use clear, descriptive commit messages.

## Style

- Use standard LaTeX conventions for tables (`booktabs`, `threeparttable` if needed).
- Figures should be referenced via `\includegraphics` pointing to `Output/Figures/`.
- Tables should be referenced via `\input` pointing to `Output/Tables/`.
- Cross-references: use `\label` and `\ref` (or `\cref` if `cleveref` is loaded).
