vim9script

if exists('g:loaded_simpleedit')
  finish
endif
g:loaded_simpleedit = 1

if v:version < 901 || !has('textprop') || !has('timers')
  echohl WarningMsg
  echomsg '[SimpleEdit] Vim 9.1 with +textprop and +timers is required.'
  echohl None
  finish
endif

g:simpleedit_yank_highlight = get(g:, 'simpleedit_yank_highlight', 1)
g:simpleedit_yank_duration = get(g:, 'simpleedit_yank_duration', 220)
g:simpleedit_unicode_filetypes = get(g:, 'simpleedit_unicode_filetypes', ['julia'])

command! SimpleEditHealth simpleedit#Health()
command! SimpleEditClearYank simpleedit#ClearYank(bufnr())

highlight default SimpleEditYank cterm=reverse gui=reverse
simpleedit#Setup()

augroup SimpleEdit
  autocmd!
  autocmd TextYankPost * simpleedit#HighlightYank()
  autocmd ColorScheme * highlight default SimpleEditYank cterm=reverse gui=reverse
augroup END
