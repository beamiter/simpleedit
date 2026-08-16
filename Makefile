.PHONY: check defcompile test regressions

check: defcompile test regressions

defcompile:
	vim -N -u NONE -n -es -S tests/defcompile.vim

test:
	vim -N -u NONE -n -es -S tests/vim_smoke.vim

regressions:
	vim -N -u NONE -n -es -S tests/regressions.vim
