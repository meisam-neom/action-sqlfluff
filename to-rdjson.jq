{
  source: {
    name: "sqlfluff-lint",
    url: "https://github.com/sqlfluff/sqlfluff"
  },
  diagnostics: [
    .[] | .violations[] as $violation | {
      message: $violation.description,
      code: {
        value: $violation.code,
        url: "https://docs.sqlfluff.com/en/stable/rules.html#rule-\($violation.code | ascii_upcase)"
      },
      location: {
        path: .filepath,
        range: {
          start: {
            line: ($violation.start_line_no // $violation.line_no // 1),
            column: ($violation.start_line_pos // $violation.line_pos // 1)
          }
        }
      },
      severity: "WARNING"
    }
  ]
}
