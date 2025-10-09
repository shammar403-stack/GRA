#!/usr/bin/env bash
# R CI bootstrap: lintr + styler + pre-commit hook + GitHub Action
set -Eeuo pipefail

echo "▶️ إعداد lintr/styler وتهيئة CI…"

# 1) .lintr
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

# 2) .Rprofile
mkdir -p .github
cat > .Rprofile <<'EOF'
if (interactive()) {
  options(
    styler.addins_style_transformer = styler::tidyverse_style(indent_by = 2, strict = TRUE),
    styler.cache_root = ".styler-cache"
  )
}
EOF

# 3) تثبيت الحزم
Rscript -e 'pkgs <- c("styler","lintr"); miss <- setdiff(pkgs, rownames(installed.packages())); if(length(miss)) install.packages(miss, repos="https://cloud.r-project.org")'

# 4) تنسيق شامل
Rscript -e 'styler::style_dir(".", filetype = c("R","Rmd"), transformers = styler::tidyverse_style(indent_by = 2, strict = TRUE))'

# 5) lintr الآن (لا يُسقط السكربت لو فيه تحذيرات)
Rscript -e 'print(lintr::lint_dir(".", exclusions = lintr::read_settings(".lintr")$exclusions))' || true

# 6) pre-commit hook
mkdir -p .git/hooks
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# التقط الملفات R/Rmd المُضافة أو المعدّلة في الـ index
mapfile -t files < <(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(R|r|Rmd|rmd)$' || true)
[ ${#files[@]} -eq 0 ] && exit 0

# نسّق الملفات المُرتبطة بالكومِت (لا تلمس غيرها)
Rscript - "$@" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
if (length(args)) {
  suppressPackageStartupMessages(library(styler))
  styler::style_file(args, transformers = styler::tidyverse_style(indent_by = 2, strict = TRUE))
}
RS
# أعدّ إضافتها بعد التنسيق
git add -- "${files[@]}"

# امنع الكومِت إذا بقيت تغييرات غير مُضافة
if ! git diff --quiet --cached; then
  echo "❌ لا تزال هناك تغييرات بعد التنسيق، راجع ثم أعد المحاولة."
  exit 1
fi
EOF
chmod +x .git/hooks/pre-commit

# 7) GitHub Action (اختياري لكنه مفيد)
mkdir -p .github/workflows
cat > .github/workflows/r-lintr.yml <<'EOF'
name: R lintr

on:
  push:
  pull_request:

jobs:
  lintr:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - name: Setup R
        uses: r-lib/actions/setup-r@v2

      - name: Cache R packages
        uses: actions/cache@v4
        with:
          path: ${{ runner.tool_cache }}/R
          key: r-${{ runner.os }}-pkgs-${{ hashFiles('**/DESCRIPTION') }}
          restore-keys: r-${{ runner.os }}-pkgs-

      - name: Install packages
        run: |
          Rscript -e 'install.packages(c("lintr"), repos="https://cloud.r-project.org")'

      - name: Run lintr
        run: |
          Rscript -e 'print(lintr::lint_dir(".")); n <- length(lintr::lint_dir(".")); if (n>0) quit(status=1) else quit(status=0)'
EOF

echo "✅ جاهز. الآن:
1) نفّذ:  git add . && git commit -m 'bootstrap R CI' && git push
2) أي كومِت لاحق سيُنسّق ملفات R تلقائيًا.
3) في GitHub → Actions سترى جوب lintr تعمل على الـ runner عندك."
