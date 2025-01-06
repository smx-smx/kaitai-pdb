using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace pdbtool
{
    public class Hasher
    {
        public static uint HashUlong(uint value)
        {
            // From Numerical Recipes in C, second edition, pg 284. 
            return value * 1664525 + 1013904223;
        }

        public static uint HashV1(Memory<byte> buf, uint modulo)
        {
            uint nWords = (uint)(buf.Length >> 2);
            throw new NotImplementedException();
        }

        public static uint HashV2(Memory<byte> buf, uint modulo)
        {
            uint hash = 0xb170a1bf;
            var dwords = MemoryMarshal.Cast<byte, uint>(buf.Span);
            foreach (var dw in dwords)
            {
                hash += dw;
                hash += (hash << 10);
                hash ^= (hash >> 6);
            }
            var remaining = buf.Span.Slice(buf.Length - buf.Length % sizeof(uint));
            foreach (var b in remaining)
            {
                hash += b;
                hash += (hash << 10);
                hash ^= (hash >> 6);
            }

            return HashUlong(hash) % modulo;
        }
    }
}
