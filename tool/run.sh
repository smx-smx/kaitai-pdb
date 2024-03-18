#!/usr/bin/env -S bash -e
kaitai-struct-compiler -t php ../pdb.ksy -- -d out
php unknown_recs.php "$1"