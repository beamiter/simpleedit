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

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/unicode_errors.log')
  cquit
endif
qa!
