#!/bin/sh

set -eu

target=${1:?usage: fixture.sh <directory>}

rm -rf "$target"
mkdir -p "$target"
cd "$target"

export GIT_AUTHOR_NAME="Test Author"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test Author"
export GIT_COMMITTER_EMAIL="test@example.com"
export GIT_AUTHOR_DATE="2026-07-20 10:00:00 +0200"
export GIT_COMMITTER_DATE="2026-07-20 11:00:00 +0200"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

git init -q --initial-branch=main
git config user.name "Test Author"
git config user.email "test@example.com"

commit() {
	printf '%s\n' "$2" > "$1"
	git add -A
	git commit -q -m "$3"
}

commit a.txt a "initial commit"
commit b.txt b "second commit"

git checkout -q -b feature
commit f.txt f "feature work"
commit f2.txt f2 "more feature work"

git checkout -q main
commit m.txt m "main work"
git merge -q --no-ff -m "merge feature" feature

git checkout -q -b topic HEAD~2
commit t.txt t "topic work"

git rebase -q main

git checkout -q main
printf 'dirty\n' >> m.txt
git stash push -q -m "work in progress"

echo "fixture built at $target"
