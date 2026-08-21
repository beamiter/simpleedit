vim9script

set nocompatible nomore virtualedit=onemore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
execute 'source ' .. fnameescape(ROOT .. '/plugin/simpleedit.vim')

new
setline(1, ['alpha', 'beta'])
setpos("'[", [0, 1, 1, 0])
setpos("']", [0, 1, 5, 0])
simpleedit#HighlightYank()
var props = prop_list(1, {types: ['SimpleEditYank']})
assert_true(!empty(props), 'TextYankPost did not highlight the yanked line')
simpleedit#ClearYank(bufnr())
assert_equal([], prop_list(1, {types: ['SimpleEditYank']}))

# A blockwise yank highlights the copied rectangle, not every byte from its
# top-left corner through the ends of the intermediate lines.
setline(1, ['abcdef', 'ghijkl', 'mnopqr'])
execute "normal! gg0\<C-V>2j2ly"
for lnum in range(1, 3)
  props = prop_list(lnum, {types: ['SimpleEditYank']})
  assert_equal(1, len(props), $'block line {lnum} has one highlight')
  assert_equal(1, props[0].col, $'block line {lnum} starts at its left edge')
  assert_equal(3, props[0].length, $'block line {lnum} keeps the block width')
endfor
simpleedit#ClearYank(bufnr())

# A block's width is in screen cells.  Byte-column endpoints from different
# lines disagree as soon as one row contains a tab and another contains a
# multibyte character; each row must be converted independently.
setlocal tabstop=8
setline(1, ['abcdef', "\tfoo", '你好foo'])
execute "normal! gg0\<C-V>3l2jy"
var expected_lengths = [4, 1, 6]
for lnum in range(1, 3)
  props = prop_list(lnum, {types: ['SimpleEditYank']})
  assert_equal(1, len(props), $'mixed-width block line {lnum} has one highlight')
  if !empty(props)
    assert_equal(1, props[0].col, $'mixed-width block line {lnum} starts at column 1')
    assert_equal(expected_lengths[lnum - 1], props[0].length,
      $'mixed-width block line {lnum} used another row''s byte width')
  endif
endfor
simpleedit#ClearYank(bufnr())

# Combining marks share the base character's cell and must be covered by the
# same block property in full.
const COMBINING_ACUTE = nr2char(0x301)
setline(1, ['e' .. COMBINING_ACUTE .. 'x', 'e' .. COMBINING_ACUTE .. 'y'])
execute "normal! gg0\<C-V>jy"
for lnum in range(1, 2)
  props = prop_list(lnum, {types: ['SimpleEditYank']})
  assert_equal(strlen('e' .. COMBINING_ACUTE), props[0].length,
    $'combining block line {lnum} did not cover the whole composed character')
endfor
simpleedit#ClearYank(bufnr())

# A short intermediate line has no byte at a block's left edge.  Highlighting
# virtual padding is impossible with a text property, but it must not throw
# from TextYankPost either.
setline(1, ['abcdef', 'g', 'mnopqr'])
execute "normal! gg02l\<C-V>2jly"
assert_equal([], prop_list(2, {types: ['SimpleEditYank']}))
simpleedit#ClearYank(bufnr())

setlocal filetype=julia
setline(1, 'x = \alpha')
cursor(1, strlen(getline(1)) + 1)
assert_equal(repeat("\<BS>", 6) .. 'α', simpleedit#UnicodeTab())
# The user's search-magic preference must not change the token grammar.
set nomagic
assert_equal(repeat("\<BS>", 6) .. 'α', simpleedit#UnicodeTab())
assert_equal(4, simpleedit#UnicodeComplete(1, ''))
set magic
setline(1, 'x = plain')
cursor(1, strlen(getline(1)) + 1)
assert_equal('', simpleedit#UnicodeTab())

# Mistyped runtime options fall back to their documented defaults instead of
# throwing from TextYankPost or an expression mapping.
g:simpleedit_unicode_filetypes = {}
setlocal filetype=julia
setline(1, 'x = \alpha')
cursor(1, strlen(getline(1)) + 1)
assert_equal(repeat("\<BS>", 6) .. 'α', simpleedit#UnicodeTab())
g:simpleedit_yank_highlight = []
g:simpleedit_yank_duration = {}
setpos("'[", [0, 1, 1, 0])
setpos("']", [0, 1, 1, 0])
try
  simpleedit#HighlightYank()
catch
  assert_report('mistyped yank options threw: ' .. v:exception)
endtry
assert_equal(1, len(prop_list(1, {types: ['SimpleEditYank']})))
simpleedit#ClearYank(bufnr())

assert_equal(2, exists(':SimpleEditHealth'))
if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
