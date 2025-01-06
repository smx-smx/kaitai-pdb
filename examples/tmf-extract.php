<?php
ini_set('memory_limit', -1);

use MsPdb\Dbi\SymbolType;
use Smx\Kaitai\KaitaiCompilerFactory;

require_once __DIR__ . '/vendor/autoload.php';

function path_combine(string ...$parts){
	return implode(DIRECTORY_SEPARATOR, $parts);
}

function compileAndLoad(){
	$file = path_combine(__DIR__, 'vendor', 'MsPdb.php');
	if(!file_exists($file)){
		$kcf = new KaitaiCompilerFactory(path_combine(__DIR__, '..', 'pdb.ksy'));
		$kcf->setOpaqueTypes(true);
		$kcf->setOutputDirectory('vendor');
		$res = $kcf->run();
		var_dump($res);
	}
	require_once __DIR__ . '/../pdb.php';
	require_once $file;
}

function methods($x){
	return array_map(
		fn($x) => $x->getName(),
		(new ReflectionClass($x))->getMethods());
}

if($argc < 2){
	fwrite(STDERR, "Usage: {$argv[0]} [file.pdb]\n");
	exit(1);
}

compileAndLoad();
/** @var MsPdb */
$pdb = MsPdb::fromFile($argv[1]);
$dbi = $pdb->dbiStream();
$modules = $dbi->modulesList()->items();
foreach($modules as $mod){
	$data = $mod->moduleData();
	if($data === null) continue;

	$symbols = $data->symbolsList();
	if($symbols === null) continue;

	$items = $symbols->items();
	foreach($items as $item){
		$data = $item->data();
		$type = $data->type();
		if($type !== SymbolType::S_ANNOTATION){
			continue;
		}
		$body = $data->body();
		$strings = $body->strings();
		print(implode(PHP_EOL, $strings) . PHP_EOL);
	}
}
