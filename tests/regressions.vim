vim9script

# Two bugs are pinned here.
#
#   1. HighlightYank() indexed getbufline(buf, lnum)[0] for every line between
#      '[ and '], and those marks outlive the lines they point at.  Shorten the
#      buffer after a yank and the index threw E684 out of TextYankPost -- and
#      the abort happened before the clearing timer was started, so the
#      properties added up to that point stayed highlighted until the next yank.
#   2. UnicodeComplete() walked all 3755 entries of the Julia symbol table on
#      every call, even for a base with no matches at all, because the 100-item
#      cap can only stop the scan for a base that has a hundred matches.  It now
#      binary-searches a sorted key list; these assertions compare it against
#      the naive scan it replaced, on the boundaries a binary search gets wrong.

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

# Long enough that no timer can fire mid-test and clear a property an assertion
# below is about to look at.  The timer is still armed, and section 1 checks it.
g:simpleedit_yank_duration = 600000
execute 'source ' .. fnameescape(ROOT .. '/plugin/simpleedit.vim')

def YankProps(lnum: number): list<dict<any>>
  return prop_list(lnum, {types: ['SimpleEditYank']})
enddef

# --- 1. Marks that outran the buffer ---------------------------------------
new
setline(1, ['alpha', 'beta', 'gamma'])
setpos("'[", [0, 1, 1, 0])
setpos("']", [0, 3, 5, 0])
deletebufline(bufnr(), 2, 3)
assert_equal(1, line('$'), 'the test needs a buffer shorter than its own "] mark')
try
  simpleedit#HighlightYank()
catch
  assert_report('"] past line("$") threw: ' .. v:exception)
endtry
# The lines that survived are still highlighted: the clamp must not turn a
# truncated range into no range at all.
assert_equal(1, len(YankProps(1)), 'the surviving line lost its highlight')
assert_equal(5, YankProps(1)[0].length)
# And the timer that removes the highlight was armed -- the throw used to skip
# it, which is what left the highlight on screen.
assert_true(getbufvar(bufnr(), 'simpleedit_yank_timer', -1) >= 0,
  'the clearing timer was never armed')
simpleedit#ClearYank(bufnr())

# Replacing a highlight must retire its timer.  ClearYank() used to set the
# buffer timer id to -1 before HighlightYank() read it, orphaning every old
# timer; when the old one expired it cleared whichever newer highlight was on
# screen at the time.
g:simpleedit_yank_duration = 10
setpos("'[", [0, 1, 1, 0])
setpos("']", [0, 1, 5, 0])
simpleedit#HighlightYank()
var retired_timer = getbufvar(bufnr(), 'simpleedit_yank_timer', -1)
g:simpleedit_yank_duration = 600000
simpleedit#HighlightYank()
var active_timer = getbufvar(bufnr(), 'simpleedit_yank_timer', -1)
assert_notequal(retired_timer, active_timer)
assert_equal([], timer_info(retired_timer), 'the replaced yank timer is still running')
sleep 30m
assert_equal(1, len(YankProps(1)), 'an old timer cleared the newer yank highlight')
assert_equal(active_timer, getbufvar(bufnr(), 'simpleedit_yank_timer', -1))
simpleedit#ClearYank(bufnr())
assert_equal([], timer_info(active_timer), ':SimpleEditClearYank left its timer running')

# Both marks past the end, at both of the boundaries range() draws.  range()
# tolerates a start exactly one past its end -- range(2, 1) is [] -- but raises
# E727 once the start is further out, so clamping last_lnum on its own is not
# enough and the function has to give up instead.  The distinction matters to
# this test: with the `first[1] > last_lnum` guard deleted, '[ = 2 below still
# passes and only '[ = 3 and '[ = 4 throw, so a one-past case on its own would
# pin the clamp without pinning the guard.
for start_lnum in [2, 3, 4]
  setline(1, ['alpha', 'beta', 'gamma', 'delta'])
  setpos("'[", [0, start_lnum, 1, 0])
  setpos("']", [0, 4, 5, 0])
  deletebufline(bufnr(), 2, 4)
  assert_equal(1, line('$'), 'the test needs a buffer shorter than its own "[ mark')
  try
    simpleedit#HighlightYank()
  catch
    assert_report(printf('"[ at %d with line("$") = 1 threw: %s', start_lnum, v:exception))
  endtry
  assert_equal([], YankProps(1),
    printf('a range with no surviving lines highlighted one ("[ = %d)', start_lnum))
endfor

# A range that ends exactly on the last line is not clamped away.
setline(1, ['alpha', 'beta'])
setpos("'[", [0, 1, 1, 0])
setpos("']", [0, 2, 4, 0])
simpleedit#HighlightYank()
assert_equal(1, len(YankProps(1)), 'first line of an in-range yank lost its highlight')
assert_equal(1, len(YankProps(2)), 'last line of an in-range yank lost its highlight')
assert_equal(4, YankProps(2)[0].length, 'the last line kept the wrong column range')
simpleedit#ClearYank(bufnr())
bwipe!

# Text properties are stored in the undo tree, but b:simpleedit_yank_timer is
# not.  Once a highlight has expired, undoing an edit made while it was alive
# must not resurrect a property with no timer left to retire it.
new
setline(1, 'alpha')
&l:undolevels = &l:undolevels
setpos("'[", [0, 1, 1, 0])
setpos("']", [0, 1, 5, 0])
simpleedit#HighlightYank()
assert_equal(1, len(YankProps(1)), 'the undo fixture was not highlighted')
normal! A!
simpleedit#ClearYank(bufnr())
assert_equal([], YankProps(1), 'the expired highlight was not cleared')
silent undo
assert_equal('alpha', getline(1))
# TextChanged is delivered on the next main-loop pass in an interactive Vim;
# a sourced headless test has no such pass, so deliver that pending event here.
doautocmd <nomodeline> TextChanged
assert_equal([], YankProps(1),
  'undo restored an expired yank highlight with no timer to clear it')
bwipe!

# --- 2. UnicodeComplete() over the prefix index ----------------------------
# Called before anything else touches the table, so this also covers the cold
# path where both the table and its key index are still empty.
new
setlocal filetype=julia
setline(1, 'x = \alp')
cursor(1, strlen(getline(1)) + 1)
assert_equal(4, simpleedit#UnicodeComplete(1, ''), 'findstart missed the backslash')
setline(1, 'no token here')
cursor(1, strlen(getline(1)) + 1)
assert_equal(0, simpleedit#UnicodeComplete(1, ''), 'findstart must fall back to 0')

const TABLE = simpleedit#julia_symbols#Get()
var sorted_keys = sort(keys(TABLE))
assert_true(len(sorted_keys) > 3000, 'the symbol table did not load')

# The scan UnicodeComplete() used to do, minus the 100-item cap: for every base
# with fewer than a hundred matches the indexed version must still return this,
# in this order.
def NaiveScan(base: string): list<string>
  var matches: list<string> = []
  for [key, value] in items(TABLE)
    if stridx(key, base) == 0
      add(matches, key .. ' ' .. value)
    endif
  endfor
  return sort(matches)
enddef

# '\alpha' is also a prefix of \alphaup etc, '\sq' has a run of its own, '\zzzz'
# has none, and the first and last keys in byte order sit at the two ends of the
# search space -- the indices an off-by-one in the binary search lands on.
for base in ['\alpha', '\al', '\sq', '\:sm', '\zzzz', '!', '~',
             sorted_keys[0], sorted_keys[-1]]
  var expected = NaiveScan(base)
  assert_true(len(expected) < 100, 'base ' .. base .. ' is capped, compare it below instead')
  assert_equal(expected, simpleedit#UnicodeComplete(0, base),
    'indexed scan disagrees with the naive one for base ' .. base)
endfor

# Case is significant: sort() and the `<` in the binary search both compare
# bytes, and 'ignorecase' must not reach either of them.
set ignorecase
assert_equal(NaiveScan('\Sq'), simpleedit#UnicodeComplete(0, '\Sq'),
  "'ignorecase' leaked into the prefix search")
assert_equal(-1, index(simpleedit#UnicodeComplete(0, '\Sq'), '\sqcap ⊓'),
  "'ignorecase' made a lower-case key match an upper-case base")
set noignorecase

# A base with more matches than the cap returns the first hundred in byte order
# -- the old code returned a hundred picked out of the dictionary's hash order.
var capped = simpleedit#UnicodeComplete(0, '\')
assert_equal(100, len(capped), 'the 100-item cap is gone')
assert_equal(NaiveScan('\')[0 : 99], capped, 'the cap no longer takes the first hundred')

# An empty base is every key, still capped, still sorted.
assert_equal(100, len(simpleedit#UnicodeComplete(0, '')), 'an empty base broke the cap')
bwipe!

if !empty(v:errors)
  writefile(v:errors, ROOT .. '/tests/errors.log')
  cquit
endif
qa!
