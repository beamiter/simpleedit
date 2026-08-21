# SimpleEdit

Small editing primitives shared by the Simple workbench:

- asynchronous yank highlighting using text properties;
- Julia-compatible LaTeX/emoji Unicode expansion through
  `simpleedit#UnicodeTab()`;
- completion data exposed without taking ownership of insert-mode mappings.

The Unicode table is generated data derived from Julia's REPL completion table
and replaces the runtime dependency on `julia-vim`.

`g:simpleedit_yank_highlight`, `g:simpleedit_yank_duration` and
`g:simpleedit_unicode_filetypes` control the runtime choices. Invalid types
fall back to `1`, `220` milliseconds and `['julia']` respectively.
