.PHONY: check defcompile test regressions visual

check: defcompile test regressions visual

defcompile:
	vim -N -u NONE -n -es -S tests/defcompile.vim

test:
	vim -N -u NONE -n -es -S tests/vim_smoke.vim

regressions:
	vim -N -u NONE -n -es -S tests/regressions.vim

# mode() is always "ce" under -es, so what depends on Visual mode needs a real
# Normal-mode session.  With stdin redirected Vim reads its keys from stderr,
# so that is redirected too: a pipe there would block a stalled run for good.
visual:
	vim -N -u NONE -n -i NONE --not-a-term -S tests/visual_yank.vim </dev/null >/dev/null 2>&1
