<?php
ini_set('memory_limit', -1);

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/../pdb.php';

// path to generated
require_once __DIR__ . '/out/MsPdb.php';

function get_methods($x){
	return array_map(fn($x) => $x->getName(), (new ReflectionClass($x))->getMethods());
}

$lfTypes = array_flip((new ReflectionClass('\MsPdb\Tpi\LeafType'))->getConstants());
$symTypes = array_flip((new ReflectionClass('\MsPdb\Dbi\SymbolType'))->getConstants());

if($argc < 2){
	fwrite(STDERR, "Usage: {$argv[0]} <file.pdb>\n");
	exit(1);
}

/** @var \MsPdb */
print("... parsing ... ");
$pdb = MsPdb::fromFile($argv[1]);
print("DONE!\n");

$debug = getenv('DEBUG') === '1';

$flags = $argv[2] ?? '';
$doSyms = empty($flags) || str_contains($flags, "+syms");
$doTypes = empty($flags) || str_contains($flags, "+types");

$seen = [];

if($doTypes){
	print("... loading types ... ");
	$types = $pdb->types();
	print("DONE!\n");
	$n_types = count($types);
	foreach($types as $i => $t){
		$d = $t->data();
		$ti = $t->ti();
		$type = $d->type();
		$body = $d->body();
	
		$klass = get_class($body);
		$isUnknown = $klass === "Pdb\LfUnknown";
		$typeName = $lfTypes[$type];
		if($isUnknown){
			printf("\n[type] i: %d, ti: %d, 0x%x %s\n", $i, $ti, $ti, $lfTypes[$type]);
			$body_data = $body->data();
			if(!isset($seen[$typeName])){
				print("\n{$typeName}\n");
				$seen[$typeName] = true;
				print(bin2hex($body_data) . "\n");
			}
			//print_r(get_methods($t));
		} else if($debug){
			//print("\33[2K\r");
			print("\r[type] {$i}/{$n_types}: {$typeName}\x1B[K");
		}
		//print(get_class($d) . "\n");
		//print_r(get_methods($d));
	}
	print("\n");
}

$handleSym = function($s, array $iModMac, array $iSymMac) use($symTypes, $debug, &$seen){
	list($iMod, $modMac) = $iModMac;
	list($iSym, $symMac) = $iSymMac;

	$sd = $s->data();
	$type = $sd->type();
	$body = $sd->body();
	$length = $sd->length();
	// no body, treat as "known"
	if($body === null) return false;

	$klass = get_class($body);
	$isUnknown = $klass === "Pdb\SymUnknown";
	$symTypeName = $symTypes[$type];
	if($isUnknown){
		$body_data = $body->data();
		if(!isset($seen[$symTypeName])){
			print("\n{$symTypeName} ({$length})\n");
			$seen[$symTypeName] = true;
			print(bin2hex($body_data) . "\n");
		}
	}
	if(!$isUnknown && $debug){
		print("\r[sym] mod: {$iMod}/{$modMac}, sym: {$iSym}/{$symMac}, {$symTypeName}\x1B[K");
	}
	return $isUnknown;
};

if($doSyms){
	do {
		print("\n... loading symbol records ... ");
		$dbi = $pdb->dbiStream();
		if($dbi === null) break;
		$sd = $dbi->symbolsData();
		print("DONE!\n");
		$syms = $sd->symbols();
		$symsMac = count($syms);
		foreach($syms as $i => $sym){
			$handleSym($sym, [-1, -1], [$i, $symsMac]);
		}
	} while(false);

	do {
		print("\n... loading symbols ... ");
		$dbi = $pdb->dbiStream();
		if($dbi === null) break;
		$mods = $dbi->modulesList()->items();
		print("DONE!\n");
		$n_mods = count($mods);
		foreach($mods as $i => $m){
			$md = $m->moduleData();
			if($md === null) continue;
			$sd = $md->symbolsList();
			if($sd === null) continue;

			$syms = $sd->items();
			$n_syms = count($syms);
			foreach($syms as $j => $s){
				$handleSym($s, [$i, $n_mods], [$j, $n_syms]);
			}
		}
	} while(false);
	print("\n");
}
