spark_locals_without_parens = [
  action: 1,
  attr: 2,
  attr: 3,
  create: 0,
  create: 1,
  function: 1,
  prototype: 1,
  prototype: 2,
  virtual: 1
]

[
  locals_without_parens: spark_locals_without_parens,
  import_deps: [:ash],
  export: [
    locals_without_parens: spark_locals_without_parens
  ],
  inputs: [".claude.exs", "{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
