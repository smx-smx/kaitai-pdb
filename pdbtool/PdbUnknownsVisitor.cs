using Kaitai;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading.Tasks;

namespace pdbtool
{
    public class PdbUnknownsVisitor
    {
        private readonly MsPdb _pdb;
        private readonly HashSet<MsPdb.Dbi.SymbolType> _symTypes;
        private readonly HashSet<MsPdb.Tpi.LeafType> _lfTypes;
        private readonly HashSet<MsPdb.Dbi.SymbolType> _seenSyms;
        private readonly HashSet<MsPdb.Tpi.LeafType> _seenTypes;
        private bool _debug = true;

        public PdbUnknownsVisitor(MsPdb pdb)
        {
            _pdb = pdb;
            _symTypes = Enum.GetValues<MsPdb.Dbi.SymbolType>().ToHashSet();
            _lfTypes = Enum.GetValues<MsPdb.Tpi.LeafType>().ToHashSet();
            _seenSyms = new HashSet<MsPdb.Dbi.SymbolType>();
            _seenTypes = new HashSet<MsPdb.Tpi.LeafType>();
        }

        private void VisitSymbol(
            MsPdb.DbiSymbol sym,
            int iMod, int modMac,
            int iSym, int symMac
        )
        {
            var sd = sym.Data;
            var type = sd.Type;
            var body = sd.Body;
            var length = sd.Length;
            
            // no body, treat as "known"
            if (body == null) return;

            var klass = body.GetType().Name;
            if(body is MsPdb.SymUnknown unk)
            {
                var bodyData = unk.Data;
                if (!_seenSyms.Contains(type))
                {
                    _seenSyms.Add(type);

                    var str = new StringBuilder("Unknown Sym: ")
                        .Append(Environment.NewLine)
                        .Append(Enum.GetName(type))
                        .AppendFormat(" ({0})", length)
                        .Append(Environment.NewLine)
                        .AppendLine(Convert.ToHexString(bodyData))
                        .ToString();

                    Console.Write(str);
                }
            } else if (_debug)
            {
                var str = new StringBuilder("\r")
                    .AppendFormat("[sym] mod: {0}/{1}, sym: {2}/{3}, {4}\x1B[K",
                        iMod, modMac,
                        iSym, symMac,
                        Enum.GetName(type)
                    ).ToString();
                Console.Write(str);
            }
            
        }

        private void VisitSymbolRecords()
        {
            var dbi = _pdb.DbiStream;
            if (dbi == null) return;

            var symbolsData = dbi.SymbolsData;
            if (symbolsData == null) return;

            var symbols = symbolsData.Symbols;
            if (symbols == null) return;

            var iSym = 0;
            foreach (var sym in symbols)
            {
                VisitSymbol(sym, -1, -1, iSym, symbols.Count);
                ++iSym;
            }
        }

        private void VisitModuleSymbols()
        {
            var dbi = _pdb.DbiStream;
            if (dbi == null) return;
            var mods = dbi.ModulesList.Items;
            var iMod = 0;
            foreach(var m in mods)
            {
                var md = m.ModuleData;
                if(md == null) continue;
                var sd = md.SymbolsList;
                if (sd == null) continue;

                var syms = sd.Items;
                var iSym = 0;
                foreach(var s in syms)
                {
                    VisitSymbol(s,
                        iSym, syms.Count,
                        iMod, mods.Count);
                    ++iSym;
                }
                ++iMod;
            }
        }

        private void VisitSymbols()
        {
            Console.WriteLine("... loading symbol records ... ");
            VisitSymbolRecords();
            Console.WriteLine("... loading symbols");
            VisitModuleSymbols();
        }

        private void VisitTypes()
        {
            var types = _pdb.Types;
            var iType = 0;
            foreach (var t in types)
            {
                var d = t.Data;
                var ti = t.Ti;
                var type = d.Type;
                var body = d.Body;

                if(body is MsPdb.LfUnknown unk)
                {
                    var str = new StringBuilder()
                        .AppendLine()
                        .AppendFormat("[type] i: {0}, ti: {1}, 0x{1:X} {2}",
                            iType, ti,
                            Enum.GetName(type)
                        )
                        .AppendLine().ToString();
                    Console.Write(str);

                    var body_data = unk.Data;
                    if (!_seenTypes.Contains(type))
                    {
                        _seenTypes.Add(type);
                        Console.Write(new StringBuilder("Unknown Type: ")
                            .Append(Environment.NewLine)
                            .AppendLine(Enum.GetName(type))
                            .AppendLine(Convert.ToHexString(body_data)));
                    }
                } else if (_debug)
                {
                    var str = new StringBuilder("\r")
                    .AppendFormat("[type] {0}/{1}: {2} \x1B[K",
                        iType, types.Count,
                        Enum.GetName(type)
                    ).ToString();
                    Console.Write(str);
                }
                ++iType;
            }
            Console.WriteLine();
        }

        public void Run()
        {
            Console.WriteLine("... loading types ...");
            VisitTypes();
            VisitSymbols();
        }
    }
}
