/**
 * THIS IS A PROTOTYPE, IT'S NOT COMPLETE
 **/

using Kaitai;
using pdbtool;


var _pdb = MsPdb.FromFile(args[0]);
SymVisitor(_pdb);

void SymVisitor(MsPdb _pdb)
{
    var visitor = new PdbUnknownsVisitor(_pdb);
    visitor.Run();
}

void TypeVisitor(MsPdb _pdb)
{
    using var tw = File.CreateText("out.h");

    new TypeNodeBuilder(_pdb).Generate();

    new PdbHeaderGenerator(_pdb, tw).Generate();
    Environment.Exit(0);

    var syms = _pdb.DbiStream.ModulesList.Items
                .Select(mod => mod?.ModuleData?.SymbolsList?.Items)
                .Where(list => list != null)
                .SelectMany(list => list!)
                .Select(sym => sym.Data.Body)
                .Where(sym => sym != null);

    foreach (var sym in syms)
    {
        switch (sym)
        {
            case MsPdb.SymCompile s:
                break;
            case MsPdb.SymCompile2 s:
                break;
            case MsPdb.SymObjname s:
                Console.WriteLine(s.Name.Value);
                break;
            case MsPdb.SymUdt s:
                Console.WriteLine(s.Name.Value);
                break;
            case MsPdb.SymData32 s:
                break;
            case MsPdb.SymProc32 s:
                break;
            case MsPdb.SymBprel32 s:
                break;
            case MsPdb.SymLabel32 s:
                break;
            case MsPdb.SymRegister32 s:
                break;
            case MsPdb.SymRegrel32 s:
                break;
            case MsPdb.SymThunk32 s:
                break;
            case MsPdb.SymConstant s:
                break;
            default:
                Console.Error.WriteLine("NOT Implemented: " + sym.GetType().FullName);
                throw new NotImplementedException(sym.GetType().FullName);
                break;
        }
    }
}