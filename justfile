alias et := ex_test
alias etwin := ex_test_win
alias t := test
alias twin := test_win
alias b := build
alias bwin := build_win

# Build the example tests that exercise testz in a real world scenario.
[working-directory: 'example']
ex_test *OPTS:
	zig build tests -- {{OPTS}}

[working-directory: 'example']
ex_test_win *OPTS:
	zig build -Dtarget=x86_64-windows-gnu tests -- {{OPTS}}

# Run the internal testz tests to check that we see the correct output for failures (captured and compared within the tests themselves).
test *OPTS:
	zig build tests -- {{OPTS}}

test_win *OPTS:
	zig build -Dtarget=x86_64-windows-gnu tests -- {{OPTS}}

build *OPTS:
	zig build {{OPTS}}

build_win *OPTS:
	zig build -Dtarget=x86_64-windows-gnu {{OPTS}}