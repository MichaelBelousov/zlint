#!/usr/bin/env -S just --justfile

set windows-shell := ["powershell"]
set shell := ["bash", "-cu"]

alias c := check
alias ck := check
alias t := test
alias b := build
alias l := lint
alias f := fmt

_default:
  @just --list -u

run:
    zig build run

build:
    zig build

check:
    @echo "Checking for AST errors..."
    @for file in `git ls-files | grep '.zig'`; do zig ast-check "$file"; done
    zig build check

watch cmd="check":
    git ls-files | entr -rc zig build {{cmd}}

test:
    zig build test

fmt:
    zig fmt src/**/*.zig
    typos -w

lint:
    zig fmt --check src/**/*.zig
    typos
