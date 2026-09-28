vim9script

# 'clipboard' autoselect fires TextYankPost from inside Visual mode without
# moving '[ and '], and HighlightYank() used to highlight the stale range they
# still held: a mouse triple click on a freshly read file put the whole buffer
# in reverse video.
#
# This runs in a real Normal-mode session rather than under -es: in Ex mode
# mode() is always "ce", so the Visual-mode check can never be exercised there.
# The price is that a script which stops early leaves Vim waiting for a key --
# and with stdin redirected Vim reads its keys from stderr, which blocks for
# good when that is a pipe.  Hence the try around the whole body, and the
# redirected stderr in the command below.
#
# Run:  vim -Nu NONE -n -i NONE --not-a-term -S tests/visual_yank.vim \
#         </dev/null >/dev/null 2>&1

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
delete(ROOT .. '/tests/errors.log')

def YankProps(): list<dict<any>>
  return prop_list(1, {types: ['SimpleEditYank'], end_lnum: line('$')})
enddef

# Fire the event the way autoselect does: from inside the selection.
def YankInside(keys: string)
  execute 'normal! gg' .. keys .. "\<Cmd>doautocmd SimpleEdit TextYankPost\<CR>\<Esc>"
enddef

def Run()
  # Long enough that no timer can clear a property an assertion is looking at.
  g:simpleedit_yank_duration = 600000
  execute 'source ' .. fnameescape(ROOT .. '/plugin/simpleedit.vim')

  new
  setline(1, ['alpha', 'beta', 'gamma'])

  # The precondition everything below depends on.
  g:simpleedit_test_mode = ''
  execute "normal! ggV\<Cmd>let g:simpleedit_test_mode = mode()\<CR>\<Esc>"
  assert_equal('V', g:simpleedit_test_mode, 'this test must not run in Ex mode')

  # The marks a file read leaves behind: first line to last.
  setpos("'[", [0, 1, 1, 0])
  setpos("']", [0, 3, 5, 0])
  for keys in ['v', 'V', "\<C-v>", 'gh', 'gH', "g\<C-h>"]
    YankInside(keys)
    assert_equal([], YankProps(),
      'a TextYankPost inside ' .. strtrans(keys) .. ' highlighted the stale marks')
    assert_equal(-1, getbufvar(bufnr(), 'simpleedit_yank_timer', -1),
      'a TextYankPost inside ' .. strtrans(keys) .. ' armed a timer')
  endfor

  # A selection must not cut short the highlight of the yank before it.
  normal! ggyy
  assert_equal(1, len(YankProps()), 'a linewise yank lost its highlight')
  var live_timer = getbufvar(bufnr(), 'simpleedit_yank_timer', -1)
  YankInside('jV')
  assert_equal(1, len(YankProps()), 'a selection cleared the live yank highlight')
  assert_equal(live_timer, getbufvar(bufnr(), 'simpleedit_yank_timer', -1),
    'a selection replaced the live yank timer')
  simpleedit#ClearYank(bufnr())

  # Operators that start from a selection have left Visual mode by the time
  # TextYankPost fires, and are highlighted as before.
  normal! ggVjy
  assert_equal([1, 2], YankProps()->mapnew((_, prop) => prop.lnum),
    'a yank from Visual mode lost its highlight')
  simpleedit#ClearYank(bufnr())
  normal! ggviwy
  assert_equal(1, len(YankProps()),
    'a characterwise yank from Visual mode lost its highlight')
  simpleedit#ClearYank(bufnr())
  bwipe!
enddef

try
  Run()
catch
  add(v:errors, v:throwpoint .. ': ' .. v:exception)
endtry
if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
