# SimpleEdit

Small editing primitives shared by the Simple workbench:

- asynchronous yank highlighting using text properties;
- Julia-compatible LaTeX/emoji Unicode expansion through
  `simpleedit#UnicodeTab()`;
- completion data exposed without taking ownership of insert-mode mappings.

The Unicode table is generated data derived from Julia's REPL completion table
and replaces the runtime dependency on `julia-vim`.
