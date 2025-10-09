#!/usr/bin/env bash
# R CI bootstrap: lintr + styler + pre-commit hook + GitHub Action
set -Eeuo pipefail

echo "▶️ إعداد R lintr/styler…"

# 1) ملفات الإعداد
cat > .lintr <<'EOF'
linters: lintr::linters_with_defaults(
  line_length_linter = lintr::line_length_linter(100),
  object_name_linter = lintr::object_name_linter(styles = "snake_case"),
  object_length_linter = lintr::object_length_linter(30),
  cyclocomp_linter = lintr::cyclocomp_linter(25),
  commented_code_linter = lintr::commented_code_linter()
)
exclusions: list(
  "data", "inst", "build", "docs"
)
EOF

mkdir -p .github && cat > .Rprofile <<'EOF'
if (interactive()) {
  options(
    styler.addins_style_transformer = styler::tidyverse_style(indent_by = 2, strict = TRUE),
    styler.cache_root = ".styler-cache"
  )
}
EOF

# 2) تثبيت الحزم المطلوبة
Rscript -e 'pkgs <- c("styler","lintr"); miss <- setdiff(pkgs, rownames(installed.packages())); if(length(miss)) install.packages(miss, repos="https://cloud.r-project.org")'

# 3) تنسيق كل ملفات R/Rmd
Rscript -e 'styler::style_dir(".", filetype = c("R","Rmd"), transformers = styler::tidyverse_style(indent_by = 2, strict = TRUE))'

# 4) تشغيل lintr الآن (لا يفشل السكربت لو فيه ملاحظات)
Rscript -e 'print(lintr::lint_dir(".", exclusions = lintr::read_settings(".lintr")$exclusions))' || true

# 5) pre-commit hook
mkdir -p .git/hooks
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(R|r|Rmd|rmd)$' || true)
[ -z "$files" ] && exit 0
Rscript - <<RS
files <- strsplit(Sys.getenv("files",""), "\\n")[[1]]
files <- files[nzchar(files)]
if (length(files)) styler::style_file(files,
