#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")"
kaitai-struct-compiler -t csharp ../pdb.ksy && ./fixsource.sh
