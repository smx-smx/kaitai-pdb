// ==UserScript==
// @name        New script kaitai.io
// @namespace   Violentmonkey Scripts
// @match       https://ide.kaitai.io/*
// @grant       none
// @version     1.0
// @author      -
// @description 14/3/2024, 22:16:25
// ==/UserScript==

(function(){
  /** UNUSED: to be removed **/
  class Concat {
    #blocks;

    constructor(items){
      this.#blocks = items.map(x => x.data);
    }
    decode(src) {
      let arr = this.#blocks.reduce((acc, curr) => {
        acc.push(...curr);
        return acc;
      }, []);
      return new Uint8Array(arr);
    }
  }

  class ConcatPages {
    #blocks;
    constructor(items){
      this.#blocks = items.map(x => x.page);
    }
    decode(src){
      let res = new Concat(this.#blocks).decode(src);
      return res;
    }
  }

  class Cat {
    #item
    constructor(item){
      this.#item = item;
    }
    decode(src){
      return this.#item;
    }
  }

  let code = `
    ${Concat.toString()}
    this.Concat = Concat;
    ${ConcatPages.toString()}
    this.ConcatPages = ConcatPages;
    ${Cat.toString()}
    this.Cat = Cat;
  `;
  localStorage.setItem('userTypes', code);
})();

