<?php
ini_set('memory_limit', -1);

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/../pdb.php';

// path to generated
require_once __DIR__ . '/out/Pdb.php';

function get_methods($x){
	return array_map(fn($x) => $x->getName(), (new ReflectionClass($x))->getMethods());
}

$lfTypes = array_flip((new ReflectionClass('\Pdb\Tpi\LeafType'))->getConstants());
$symTypes = array_flip((new ReflectionClass('\Pdb\Dbi\SymbolType'))->getConstants());

if($argc < 2){
	fwrite(STDERR, "Usage: {$argv[0]} <file.pdb>\n");
	exit(1);
}

/** @var \Pdb */
$pdb = Pdb::fromFile($argv[1]);

$seen = [];

$types = $pdb->types();
foreach($types as $i => $t){
	$d = $t->data();
	$ti = $t->ti();
	$type = $d->type();
	$body = $d->body();
	if(get_class($body) === "Pdb\LfUnknown"){
		printf("[type] i: %d, ti: %d, 0x%x %s\n", $i, $ti, $ti, $lfTypes[$type]);
		$body_data = $body->data();
		$typeName = $lfTypes[$d->type()];
		if(!isset($seen[$typeName])){
			print("{$typeName}\n");
			$seen[$typeName] = true;
			print(bin2hex($body_data) . "\n");
		}
		//print_r(get_methods($t));
	}
	//print(get_class($d) . "\n");
	//print_r(get_methods($d));
}

$mods = $pdb->dbi()->modules()->modules();
foreach($mods as $i => $m){
	$md = $m->moduleData();
	if($md === null) continue;
	$sd = $md->symbols();
	if($sd === null) continue;
	
	$syms = $sd->symbols();
	foreach($syms as $j => $s){
		$sd = $s->data();
		$type = $sd->type();
		$body = $sd->body();
		if($body === null) continue;
		if(get_class($body) === "Pdb\SymUnknown"){
			$body_data = $body->data();
			$symTypeName = $symTypes[$type];
			//printf("[sym] mod: %d, sym: %d, %s\n", $i, $j, $symTypeName);
			if(!isset($seen[$symTypeName])){
				print("{$symTypeName}\n");
				$seen[$symTypeName] = true;
				print(bin2hex($body_data) . "\n");
			}
		}
	}
}