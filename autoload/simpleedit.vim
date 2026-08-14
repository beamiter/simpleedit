vim9script

var s_unicode: dict<string> = {}

export def Setup()
  if empty(prop_type_get('SimpleEditYank'))
    prop_type_add('SimpleEditYank', {highlight: 'SimpleEditYank', combine: true})
  endif
enddef

export def ClearYank(buf: number)
  if !bufexists(buf)
    return
  endif
  prop_remove({type: 'SimpleEditYank', bufnr: buf, all: true}, 1, getbufinfo(buf)[0].linecount)
  setbufvar(buf, 'simpleedit_yank_timer', -1)
enddef

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

export def HighlightYank()
  if !get(g:, 'simpleedit_yank_highlight', 1)
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
  var regtype = get(v:event, 'regtype', '')
  for lnum in range(first[1], last[1])
    var text = getbufline(buf, lnum)[0]
    if regtype =~# '^V'
      AddYankLine(buf, lnum, 1, max([1, strlen(text)]))
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
  var old_timer = getbufvar(buf, 'simpleedit_yank_timer', -1)
  if type(old_timer) == v:t_number && old_timer >= 0
    timer_stop(old_timer)
  endif
  var duration = get(g:, 'simpleedit_yank_duration', 220)
  var timer = timer_start(max([1, duration]), (_) => ClearYank(buf))
  setbufvar(buf, 'simpleedit_yank_timer', timer)
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
  if index(get(g:, 'simpleedit_unicode_filetypes', ['julia']), &l:filetype) < 0
    return ''
  endif
  var byte_col = col('.') - 1
  var before = strpart(getline('.'), 0, byte_col)
  var token = matchstr(before, '\\\%(:[^[:space:]\\]*:\|[^[:space:]\\]*\)$')
  if empty(token)
    return ''
  endif
  var replacement = get(UnicodeTable(), token, '')
  if empty(replacement)
    return ''
  endif
  return repeat("\<BS>", strlen(token)) .. replacement
enddef

export def UnicodeComplete(findstart: number, base: string): any
  if findstart
    var before = strpart(getline('.'), 0, col('.') - 1)
    return max([0, match(before, '\\[^[:space:]\\]*$')])
  endif
  var matches: list<string> = []
  for [key, value] in items(UnicodeTable())
    if stridx(key, base) == 0
      add(matches, key .. ' ' .. value)
    endif
    if len(matches) >= 100
      break
    endif
  endfor
  return sort(matches)
enddef

export def Health()
  Setup()
  echomsg 'SimpleEdit health'
  echomsg $'  yank highlight: {get(g:, "simpleedit_yank_highlight", 1) ? "enabled" : "disabled"}'
  echomsg $'  text properties: {has("textprop") ? "yes" : "no"}'
  echomsg $'  Unicode symbols: {len(UnicodeTable())}'
enddef
