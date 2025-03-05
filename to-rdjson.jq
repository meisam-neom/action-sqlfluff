{
  source: {
    name: "sqlfluff",
    url: "https://github.com/sqlfluff/sqlfluff"
  },
  diagnostics: (. // {}) | map(. as $file | $file.violations[] as $violation | {
    message: $violation.description,
    code: {
      value: $violation.code,
      url: "https://docs.sqlfluff.com/en/stable/reference/rules.html#sqlfluff.core.rules.Rule_\($violation.code)"
    },
    location: {
      path: $file.filepath,
      range: {
        start: {
          line: ($violation.start_line_no // $violation.line_no // 1),
          column: ($violation.start_line_pos // $violation.line_pos // 1)
        },
      }
    },
    severity: "WARNING",
  })
}