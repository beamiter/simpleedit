vim9script

set nocompatible nomore encoding=utf-8
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
execute 'source ' .. fnameescape(ROOT .. '/plugin/simpleedit.vim')
new
setlocal filetype=julia
# Flush preceding Insert input before evaluating the expression mapping, as
# separate physical keystrokes would do.
imap <F5> <Ignore><F6>
inoremap <expr> <F6> simpleedit#UnicodeTab()

# Drive the returned keys in real Insert mode, not just the expansion string.
# At the insertion boundary <BS> may refuse all or part of the token.
for policy in ['', '0', '1', 'indent,eol']
  &backspace = policy
  var normalized = &backspace
  setline(1, 'x = \alpha')
  feedkeys("A\<F5>\<Esc>", 'xt')
  assert_equal('x = \alpha', getline(1), 'do not append a symbol to an old token')
  assert_equal(normalized, &backspace, 'expansion must not change backspace')
  setline(1, 'x = \al')
  feedkeys("Apha\<F5>\<Esc>", 'xt')
  assert_equal('x = \alpha', getline(1), 'do not replace only the new token suffix')
  setline(1, 'x = ')
  feedkeys("A\\alpha\<F5>\<Esc>", 'xt')
  assert_equal('x = \alpha', getline(1), 'new tokens use the documented fallback too')
endfor

for policy in ['2', '3', 'indent,eol,start', 'indent,eol,nostop']
  &backspace = policy
  var normalized = &backspace
  for initial in ['x = \alpha', 'x = \al']
    setline(1, initial)
    var suffix = initial ==# 'x = \al' ? 'pha' : ''
    feedkeys('A' .. suffix .. "\<F5>\<Esc>", 'xt')
    assert_equal('x = α', getline(1), 'permitted expansion: ' .. policy .. ' initial=' .. initial)
    assert_equal(normalized, &backspace)
  endfor
endfor

# Replace-mode backspace restores overwritten source text instead of deleting
# the token. Declining expansion must leave the typed token and its suffix
# intact rather than restoring old text and overwriting only its first char.
set backspace=indent,eol,start
for start in ['R', 'gR']
  setline(1, 'abcdefXYZ')
  cursor(1, 1)
  feedkeys(start .. "\\alpha\<F5>\<Esc>", 'xt')
  assert_equal('\alphaXYZ', getline(1), start .. ' expansion damaged replaced text')
endfor

# Real mapping control: slicing at the oldest possible byte must not turn an
# incomplete or long unknown token into a shorter recognized suffix.
const HAN = nr2char(0x754c)
const LONGER = '\:' .. repeat('z', 128) .. ':'
const LEFT = repeat(HAN, 24) .. '中文'
const MIXED: list<list<string>> = [
  ['\alpha', 'α'],
  ['\^2', '²'],
  ['\:smile:', '😄'],
  ['\:smile', '\:smile'],
  ['\alphaZ', '\alphaZ'],
  [LONGER, LONGER],
  ['\unknown\alpha', '\unknownα'],
  ['\alpha ', '\alpha '],
]
for [token, expanded] in MIXED
  setline(1, LEFT .. token)
  feedkeys("A\<F5>\<Esc>", 'xt')
  assert_equal(LEFT .. expanded, getline(1), token)
endfor

# Do not read a valid continuation to the RIGHT of the cursor, or erase
# existing text after a successful conversion.
setline(1, '\alp' .. 'ha')
cursor(1, 5)
feedkeys("i\<F5>\<Esc>", 'xt')
assert_equal('\alpha', getline(1), 'do not expand a cursor-mid-token prefix')
setline(1, LEFT .. '\alpha#tail')
cursor(1, strlen(LEFT .. '\alpha') + 1)
feedkeys("i\<F5>\<Esc>", 'xt')
assert_equal(LEFT .. 'α#tail', getline(1), 'keep right-hand text at the cursor')

# Exercise every generated symbol including the exact maximum, not a hand-
# picked length sample; a table update must keep the token bound in sync.
for [token, replacement] in items(simpleedit#julia_symbols#Get())
  setline(1, LEFT .. token .. '#')
  cursor(1, strlen(LEFT .. token) + 1)
  assert_equal(repeat("\<BS>", strlen(token)) .. replacement,
    simpleedit#UnicodeTab(), 'generated symbol: ' .. token)
endfor

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/unicode_errors.log')
  cquit
endif
qa!
