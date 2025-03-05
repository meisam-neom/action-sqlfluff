{
  source: {
    name: "sqlfluff",
    url: "https://github.com/sqlfluff/sqlfluff"
  },
  diagnostics: [
    .[] | .violations[] | {
      message: .description,
      code: {
        value: .code,
        url: "https://docs.sqlfluff.com/en/stable/rules.html#rule-\(.code | ascii_upcase)"
      },
      location: {
        path: .filepath,
        range: {
          start: {
            line: (.start_line_no // .line_no // 1),
            column: (.start_line_pos // .line_pos // 1)
          }
        }
      },
      severity: "WARNING"
    }
  ]
}
