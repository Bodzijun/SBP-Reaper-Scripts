import assert from 'node:assert/strict';
import vm from 'node:vm';
// EEL '%' operates on integer absolute values. In these arithmetic fixtures all
// remaining modulo operands must already be integer indices/counters.
export function eelModulo(numerator,denominator){
 assert(Number.isInteger(numerator)&&Number.isInteger(denominator),'EEL modulo received a fractional operand; JS remainder would hide truncation');
 return Math.trunc(Math.abs(numerator))%Math.trunc(Math.abs(denominator));
}
export function arithmeticBody(source,name){
 const at=source.indexOf(`function ${name}(`),global=source.indexOf('global()',at),open=source.indexOf('(',global+8);
 assert(at>=0&&global>at&&open>global);
 let code=source.slice(open+1,source.indexOf('\n);',open)).replace(/\/\/[^\n]*/g,'');
 code=code.replace(/\((index\+size-1|index\+1|index\+2)\)%size/g,(_,expr)=>`eelModulo(${expr},size)`)
  .replace(/\(write_pos\+1\)%length/g,'eelModulo(write_pos+1,length)');
 assert(!code.includes('%'),`Unmodelled EEL modulo in ${name}`);
 return new vm.Script(code);
}
