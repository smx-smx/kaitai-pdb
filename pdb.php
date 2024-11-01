<?php
/**
 * @author Stefano Moioli <smxdev4@gmail.com>
 */

namespace MsPdb {
	class Concat {
		private $blocks;
		public function __construct($items){
			$this->blocks = array_map(fn($x) => $x->data(), $items);
		}
		public function decode($src){
			return implode('', $this->blocks);
		}
	}

	class ConcatPages {
		private $blocks;
		public function __construct($items){
			$this->blocks = array_map(fn($x) => $x->page(), $items);
		}
		public function decode($src){
			return (new Concat($this->blocks))->decode($src);
		}
	}

	class Cat {
		private $item;
		public function __construct($item){
			$this->item = $item;
		}
		public function decode($src){
			return $this->item;
		}
	}
}

namespace {
	class Cat {
		private $item;
		public function __construct($item){
			$this->item = $item;
		}
		public function decode($src){
			return $this->item;
		}
	}
}