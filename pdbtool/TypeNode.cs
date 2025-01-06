using Kaitai;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace pdbtool
{
    internal record TypeNode(KaitaiStruct type)
    {
        public IList<TypeNode> XRefs = new List<TypeNode>();
    }
}
