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

setlocal filetype=julia
setline(1, 'x = \alpha')
cursor(1, strlen(getline(1)) + 1)
assert_equal(repeat("\<BS>", 6) .. 'α', simpleedit#UnicodeTab())
setline(1, 'x = plain')
cursor(1, strlen(getline(1)) + 1)
assert_equal('', simpleedit#UnicodeTab())

assert_equal(2, exists(':SimpleEditHealth'))
if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
