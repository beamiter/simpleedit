vim9script

var s_unicode: dict<string> = {}
var s_unicode_keys: list<string> = []

export def Setup()
  if empty(prop_type_get('SimpleEditYank'))
    prop_type_add('SimpleEditYank', {highlight: 'SimpleEditYank', combine: true})
  endif
enddef

def RemoveYank(buf: number)
  # A timer may outlive an unloaded (but still existing) buffer.  Text
  # properties cannot be inspected in that state, and unloading has already
  # discarded the visible highlight anyway.
  if !bufloaded(buf)
    return
  endif
  var info = getbufinfo(buf)
  if empty(info)
    return
  endif
  prop_remove({type: 'SimpleEditYank', bufnr: buf, all: true}, 1, info[0].linecount)
enddef

export def ClearYank(buf: number)
  if !bufexists(buf)
    return
  endif
  # Stop the owner before clearing its id.  HighlightYank() calls this before
  # every new yank; clearing the id first used to orphan the previous timer,
  # which then fired during the new highlight and removed it early.
  var timer = getbufvar(buf, 'simpleedit_yank_timer', -1)
  if type(timer) == v:t_number && timer >= 0
    # Text properties are undoable, buffer variables are not.  Fence the undo
    # sequence whose highlight is being retired so the TextChanged hook below
    # can distinguish a real undo from ordinary typing without sweeping the
    # whole buffer on every change.
    var retired_seq = buf == bufnr()
      ? get(undotree(), 'seq_cur', 0)
      : getbufvar(buf, 'simpleedit_yank_owner_seq', -1)
    if type(retired_seq) == v:t_number && retired_seq >= 0
      setbufvar(buf, 'simpleedit_yank_retired_seq', retired_seq)
    endif
  endif
  setbufvar(buf, 'simpleedit_yank_timer', -1)
  setbufvar(buf, 'simpleedit_yank_owner_seq', -1)
  if type(timer) == v:t_number && timer >= 0
    timer_stop(timer)
  endif
  RemoveYank(buf)
enddef

# Text properties participate in Vim's undo history, while the timer id in a
# buffer variable does not.  A highlight that has already expired can
# therefore come back when the text edit made while it was visible is undone.
# TextChanged runs for that undo; if no timer still owns the highlight, remove
# any property the undo state restored.  Live highlights keep their original
# duration and are allowed to follow ordinary edits until the timer fires.
export def PruneExpiredYank(buf: number)
  if !bufexists(buf) || buf != bufnr()
    return
  endif
  var timer = getbufvar(buf, 'simpleedit_yank_timer', -1)
  if type(timer) == v:t_number && timer >= 0
    # Remember edits made while the live property is present.  The timer may
    # later fire while another buffer is current, where undotree() cannot
    # inspect this buffer directly.
    setbufvar(buf, 'simpleedit_yank_owner_seq',
      get(undotree(), 'seq_cur', 0))
    return
  endif
  var retired_seq = getbufvar(buf, 'simpleedit_yank_retired_seq', -1)
  if type(retired_seq) == v:t_number && retired_seq >= 0
      && get(undotree(), 'seq_cur', retired_seq) < retired_seq
    RemoveYank(buf)
  endif
enddef

def OnYankTimeout(buf: number, timer: number)
  # A stopped timer should not run, but the id check also makes a late callback
  # harmless if Vim had already queued it when a newer yank replaced it.
  if !bufexists(buf) || getbufvar(buf, 'simpleedit_yank_timer', -1) != timer
    return
  endif
  var retired_seq = buf == bufnr()
    ? get(undotree(), 'seq_cur', 0)
    : getbufvar(buf, 'simpleedit_yank_owner_seq', -1)
  if type(retired_seq) == v:t_number && retired_seq >= 0
    setbufvar(buf, 'simpleedit_yank_retired_seq', retired_seq)
  endif
  setbufvar(buf, 'simpleedit_yank_timer', -1)
  setbufvar(buf, 'simpleedit_yank_owner_seq', -1)
  RemoveYank(buf)
enddef

# One prop_add() per line, deliberately, rather than the batched
# prop_add_list(): a linewise yank leaves '] in column v:maxcol, prop_add()
# clamps a `length` that large to the end of the line, and prop_add_list()
# rejects the equivalent end-col of v:maxcol + 1 with E474 -- another throw out
# of TextYankPost, the failure the clamp in HighlightYank() below exists to
# prevent.  Batching was measured before it was rejected: 0.7 ms off the 17.5 ms
# a 20000-line linewise yank spends here, 4%, which does not buy that.
def AddYankLine(buf: number, lnum: number, col: number, length: number)
  if length <= 0
    return
  endif
  prop_add(lnum, max([1, col]), {
    type: 'SimpleEditYank',
    length: length,
    bufnr: buf,
  })
enddef

# Highlight the bytes whose displayed cells intersect one row of a blockwise
# yank.  A block is measured in virtual columns, not byte columns: the two end
# marks can sit on different lines with different tabs or multibyte characters,
# so subtracting their byte columns made the width of one endpoint leak onto
# every row.  A text property cannot colour half a tab or wide character; it
# colours that whole character, which is the closest faithful representation.
def AddYankBlockLine(buf: number, lnum: number, left: number, right: number)
  var text = getbufline(buf, lnum)[0]
  if empty(text) || left >= virtcol([lnum, '$'])
    return
  endif
  var start_col = virtcol2col(0, lnum, left)
  var end_col = virtcol2col(0, lnum, right)
  if start_col <= 0 || end_col < start_col
    return
  endif
  # Include combining marks / variation selectors attached to the final base
  # character.  They occupy the same cell and were part of the block yank, but
  # byte-counting only the base left most of the grapheme unhighlighted.
  var end_char = strcharpart(strpart(text, end_col - 1), 0, 1, true)
  AddYankLine(buf, lnum, start_col,
    end_col - start_col + max([1, strlen(end_char)]))
enddef

def YankEnabled(): bool
  var configured: any = get(g:, 'simpleedit_yank_highlight', 1)
  if type(configured) == v:t_bool
    return configured
  endif
  return type(configured) == v:t_number ? configured != 0 : true
enddef

def YankDuration(): number
  var configured: any = get(g:, 'simpleedit_yank_duration', 220)
  return type(configured) == v:t_number && configured > 0 ? configured : 220
enddef

def UnicodeFiletypes(): list<string>
  var configured: any = get(g:, 'simpleedit_unicode_filetypes', ['julia'])
  if type(configured) != v:t_list
    return ['julia']
  endif
  var filetypes: list<string> = []
  for value in configured
    if type(value) == v:t_string
      add(filetypes, value)
    endif
  endfor
  return filetypes
enddef

export def HighlightYank()
  if !YankEnabled()
    return
  endif
  Setup()
  var buf = bufnr()
  ClearYank(buf)
  var first = getpos("'[")
  var last = getpos("']")
  if first[1] <= 0 || last[1] < first[1]
    return
  endif
  # The '[ and '] marks outlive the lines they point at.  A yank whose range is
  # shortened before this autocmd runs -- another TextYankPost handler deleting
  # lines, an undo, a yank in a buffer a plugin is rewriting -- leaves '] past
  # line('$'), getbufline() returns an empty list for those lines, and indexing
  # it threw E684 from inside TextYankPost.  That abort also skipped the timer
  # below, so the properties added before the throw were never cleared and the
  # highlight stayed on screen until the next yank.  Clamp to the lines that
  # still exist, and give up when even '[ is gone: range() tolerates a start
  # exactly one past its end -- range(2, 1) is [] -- but raises E727 once the
  # start is further out than that, so clamping last_lnum on its own would have
  # swapped E684 for E727 whenever '[ landed two or more lines past the end.
  var last_lnum = min([last[1], line('$')])
  if first[1] > last_lnum
    return
  endif
  var regtype = get(v:event, 'regtype', '')
  for lnum in range(first[1], last_lnum)
    var text = getbufline(buf, lnum)[0]
    if regtype =~# '\m^V'
      AddYankLine(buf, lnum, 1, max([1, strlen(text)]))
    elseif strpart(regtype, 0, 1) ==# "\<C-V>"
      # A blockwise yank is a rectangle.  Treating it as a multi-line
      # characterwise yank highlighted from the opening corner to end-of-line
      # on every line except the last often coloured most of the screen rather
      # than what was copied.  Convert its screen-cell width on each row; byte
      # columns from the two endpoint lines are not interchangeable.
      var width = str2nr(strpart(regtype, 1))
      var left = min([virtcol("'["), virtcol("']")])
      if width <= 0
        width = abs(virtcol("']") - virtcol("'[")) + 1
      endif
      AddYankBlockLine(buf, lnum, left, left + width - 1)
    elseif first[1] == last[1]
      AddYankLine(buf, lnum, first[2], max([1, last[2] - first[2] + 1]))
    elseif lnum == first[1]
      AddYankLine(buf, lnum, first[2], max([1, strlen(text) - first[2] + 1]))
    elseif lnum == last[1]
      AddYankLine(buf, lnum, 1, max([1, last[2]]))
    else
      AddYankLine(buf, lnum, 1, max([1, strlen(text)]))
    endif
  endfor
  var timer = timer_start(YankDuration(), (expired) => OnYankTimeout(buf, expired))
  setbufvar(buf, 'simpleedit_yank_timer', timer)
  if timer < 0
    setbufvar(buf, 'simpleedit_yank_owner_seq', -1)
    RemoveYank(buf)
    return
  endif
  setbufvar(buf, 'simpleedit_yank_owner_seq',
    get(undotree(), 'seq_cur', 0))
enddef

def UnicodeTable(): dict<string>
  if empty(s_unicode)
    var loaded = simpleedit#julia_symbols#Get()
    if type(loaded) == v:t_dict
      s_unicode = loaded
    endif
  endif
  return s_unicode
enddef

export def UnicodeTab(): string
  if index(UnicodeFiletypes(), &l:filetype) < 0
    return ''
  endif
  var byte_col = col('.') - 1
  var before = strpart(getline('.'), 0, byte_col)
  var token = matchstr(before, '\m\\\%(:[^[:space:]\\]*:\|[^[:space:]\\]*\)$')
  if empty(token)
    return ''
  endif
  var replacement = get(UnicodeTable(), token, '')
  if empty(replacement)
    return ''
  endif
  return repeat("\<BS>", strlen(token)) .. replacement
enddef

# The table's keys in byte order, sorted once.  sort() without {how} compares
# with strcmp() and ignores 'ignorecase', so every key sharing a prefix lands in
# one contiguous run -- which is what lets UnicodeComplete() stop early instead
# of reading all 3755 entries.
def UnicodeKeys(): list<string>
  if empty(s_unicode_keys)
    s_unicode_keys = sort(keys(UnicodeTable()))
  endif
  return s_unicode_keys
enddef

# Nothing in the Simple suite calls this: simplecc drives Unicode expansion
# through UnicodeTab() from an <expr> mapping.  It stays because it is a public
# autoload function that a vimrc can point 'completefunc' at, and deleting it on
# a user we cannot see costs more than keeping twenty lines.
#
# It used to walk every entry of the table on each keystroke, 0.6 ms per call
# even for a base with no matches at all, because the 100-item cap only stops
# the scan for bases with a hundred matches.  The keys are sorted, so the
# matches for a base are one contiguous run: a binary search finds where that
# run starts and the walk ends at the first key that leaves it -- 0.004 ms for
# a specific token, 0.034 ms for a bare backslash.  The result is unchanged for
# every base with fewer than 100 matches (sorting "key value" strings orders
# them the same way as sorting the keys, since no key contains a space); for the
# short bases that overflow the cap it is now the first hundred in byte order
# rather than a hundred picked out of the dictionary's hash order.
export def UnicodeComplete(findstart: number, base: string): any
  if findstart
    var before = strpart(getline('.'), 0, col('.') - 1)
    return max([0, match(before, '\m\\[^[:space:]\\]*$')])
  endif
  var table = UnicodeTable()
  var sorted_keys = UnicodeKeys()
  var lo = 0
  var hi = len(sorted_keys)
  while lo < hi
    var mid = (lo + hi) / 2
    if sorted_keys[mid] < base
      lo = mid + 1
    else
      hi = mid
    endif
  endwhile
  var matches: list<string> = []
  while lo < len(sorted_keys) && len(matches) < 100
    var key = sorted_keys[lo]
    if stridx(key, base) != 0
      break
    endif
    add(matches, key .. ' ' .. table[key])
    lo += 1
  endwhile
  return matches
enddef

export def Health()
  Setup()
  echomsg 'SimpleEdit health'
  echomsg $'  yank highlight: {YankEnabled() ? "enabled" : "disabled"}'
  echomsg $'  text properties: {has("textprop") ? "yes" : "no"}'
  echomsg $'  Unicode symbols: {len(UnicodeTable())}'
enddef
