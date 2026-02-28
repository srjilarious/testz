alias et := ex_test
alias t := test
alias b := build
alias bwin := build_win
alias rwin := run_win

# Build the example tests that exercise testz in a real world scenario.
[working-directory: 'example']
ex_test *OPTS:
	zig build tests -- {{OPTS}}

# Run the internal testz tests to check that we see the correct output for failures (captured and compared within the tests themselves).
test *OPTS:
	zig build tests -- {{OPTS}}

build EX *OPTS:
	zig build {{EX}} {{OPTS}}

build_win *EX:
	zig build {{EX}} -Dtarget=x86_64-windows-msvc 

run_win EX:
	wine zig-out/bin/{{EX}}.exe