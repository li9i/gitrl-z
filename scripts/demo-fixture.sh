#!/bin/sh

set -eu

target=${1:?usage: demo-fixture.sh <directory>}

if [ -e "$target" ]; then
	echo "demo-fixture.sh: $target exists already; remove it or name another path" >&2
	exit 1
fi

mkdir -p "$target"
cd "$target"

export GIT_AUTHOR_NAME="Ada Lovelace"
export GIT_AUTHOR_EMAIL="ada@example.com"
export GIT_COMMITTER_NAME="Ada Lovelace"
export GIT_COMMITTER_EMAIL="ada@example.com"
export GIT_AUTHOR_DATE="2026-07-20 10:00:00 +0200"
export GIT_COMMITTER_DATE="2026-07-20 10:00:00 +0200"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

git init -q --initial-branch=main
git config user.name "Ada Lovelace"
git config user.email "ada@example.com"

commit() {
	printf '%s\n' "$2" > "$1"
	git add -A
	git commit -q -m "$3"
}

commit README.md readme "initial commit"
commit parser.py parser "add the parser"

git checkout -q -b feature
commit lexer.py lexer "add the lexer"
commit test_lexer.py lexed "test the lexer"

git checkout -q main
commit Makefile rules "add the build rules"
git merge -q --no-ff -m "merge feature" feature

git checkout -q -b topic "$(git rev-parse main~2)"
commit report.md report "add the report"
commit test_report.py reported "test the report"
git rebase -q main

git checkout -q main
commit manual.md manual "write the manual"
commit CHANGELOG.md changelog "write the changelog"
git reset -q --hard HEAD~2

git checkout -q -b spike
commit parser.py spiked "try another approach"

git checkout -q main
git branch -q -D spike

echo "demo repository built at $target"
