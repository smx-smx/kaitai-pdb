using Kaitai;
using System;
using System.Collections.Generic;
using System.Data.SqlTypes;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace pdbtool
{
    interface IPdbTypeVisitor
    {
        void VisitEnum(MsPdb.LfEnum item);
        void VisitEnumerate(MsPdb.LfEnumerate item);
        void VisitFieldList(MsPdb.LfFieldlist item);
        void VisitClass(MsPdb.LfClass item);
        void VisitType(KaitaiStruct type);
        void VisitUnion(MsPdb.LfUnion item);
        void VisitVtshape(MsPdb.LfVtshape item);
        void VisitMember(MsPdb.LfMember item);
        void VisitPointer(MsPdb.LfPointer item);
    }

    class PdbTypeVisitorBase : IPdbTypeVisitor
    {
        public virtual void VisitClass(MsPdb.LfClass item)
        {
        }

        public virtual void VisitEnum(MsPdb.LfEnum item)
        {
        }

        public virtual void VisitEnumerate(MsPdb.LfEnumerate item)
        {
        }

        public virtual void VisitFieldList(MsPdb.LfFieldlist item)
        {
        }

        public virtual void VisitType(KaitaiStruct type)
        {
            switch (type)
            {
                case MsPdb.LfMember i:
                    VisitMember(i);
                    break;
                case MsPdb.LfUnknown i:
                    break;
                case MsPdb.LfOneMethod i:
                    break;
                case MsPdb.LfEnumerate i:
                    VisitEnumerate(i);
                    break;
                case MsPdb.LfEnum i:
                    VisitEnum(i);
                    break;
                case MsPdb.LfFieldlist i:
                    VisitFieldList(i);
                    break;
                case MsPdb.LfClass i:
                    VisitClass(i);
                    break;
                case MsPdb.LfPointer i:
                    VisitPointer(i);
                    break;
                case MsPdb.LfArglist i:
                    break;
                case MsPdb.LfProcedure i:
                    break;
                case MsPdb.LfArray i:
                    break;
                case MsPdb.LfMfunction i:
                    break;
                case MsPdb.LfModifier i:
                    break;
                case MsPdb.LfMethodlist i:
                    break;
                case MsPdb.LfUnion i:
                    VisitUnion(i);
                    break;
                case MsPdb.LfBitfield i:
                    break;
                case MsPdb.LfVtshape i:
                    VisitVtshape(i);
                    break;
                default:
                    throw new NotImplementedException(type.GetType().FullName);
            }
        }

        public virtual void VisitVtshape(MsPdb.LfVtshape item)
        {
        }

        public virtual void VisitUnion(MsPdb.LfUnion item)
        {
        }

        public virtual void VisitMember(MsPdb.LfMember item)
        {
        }

        public virtual void VisitPointer(MsPdb.LfPointer item)
        {
        }
    }

    internal class EnumVisitor : PdbTypeVisitorBase
    {

    }

    class TypeSpec
    {
        private readonly string _name;
        private readonly KaitaiStruct _type;
        private readonly IDictionary<string, TypeSpec> _children;

        public string Name => _name;
        public KaitaiStruct Type => _type;

        public TypeSpec(string name, KaitaiStruct type)
        {
            _name = name;
            _type = type;
            _children = new Dictionary<string, TypeSpec>();
        }

        public void AddType(TypeSpec type)
        {
            _children[type._name] = type;
        }
    }

    class TypeNodeBuilder : PdbTypeVisitorBase
    {
        private IDictionary<string, TypeNode> _nodes = new Dictionary<string, TypeNode>();
        //private IList<TypeNode> _roots = new List<TypeNode>();

        private readonly MsPdb _pdb;
        public TypeNodeBuilder(MsPdb pdb)
        {
            _pdb = pdb;
        }

        private TypeNode? GetNode(KaitaiStruct obj)
        {
            var name = GetName(obj);
            if (name == null) return null;
            if (_nodes.TryGetValue(name, out var node)) return node;
            node = new TypeNode(obj);
            _nodes.Add(name, node);
            return node;
        }

        private string? GetName(KaitaiStruct obj)
        {
            switch (obj)
            {
                case MsPdb.LfFieldlist:
                case MsPdb.LfVtshape:
                    return null;
                default:
                    throw new NotImplementedException(obj.GetType().FullName);
            }
        }

        public override void VisitEnum(MsPdb.LfEnum item)
        {
            if (item.TypeProperties.ForwardReference) return;

        }

        public override void VisitClass(MsPdb.LfClass item)
        {
            if (item.Properties.ForwardReference) return;
            if (item.Name.Value.Contains("::__unnamed")
                || item.Name.Value.Contains("::<unnamed-tag>")) return;

            var node = new TypeNode(item);
            var derivedType = item.DerivedType.Type?.Data?.Body;
            if (derivedType != null)
            {
                var derived = GetNode(derivedType);
                if (derived != null)
                {
                    node.XRefs.Add(derived);
                }
                VisitType(derivedType);
            }
            var vshapeType = item.VshapeType.Type?.Data?.Body;
            if (vshapeType != null)
            {
                var vshape = GetNode(vshapeType);
                if (vshape != null)
                {
                    node.XRefs.Add(vshape);
                }
                VisitType(vshapeType);
            }
            var fieldType = item.FieldType.Type?.Data?.Body;
            if (fieldType != null)
            {
                var field = GetNode(fieldType);
                if (field != null)
                {
                    node.XRefs.Add(field);
                }
                VisitType(fieldType);
            }

            if (_nodes.ContainsKey(item.Name.Value)) return;
            _nodes.Add(item.Name.Value, node);
        }

        public void Generate()
        {
            foreach (var t in _pdb.TpiStream.Types.Types.Select(t => t.Data.Body))
            {
                VisitType(t);
            }
        }
    }

    internal class PdbHeaderGenerator : PdbTypeVisitorBase
    {
        private readonly MsPdb _pdb;
        private readonly TextWriter _tw;

        private void EmitPacked()
        {
            _tw.Write("__attribute__((packed))");
        }

        private HashSet<string> handledTemplates = new HashSet<string>();

        private IList<MsPdb.LfClass> _deferredClasses = new List<MsPdb.LfClass>();
        private IList<MsPdb.LfEnum> _deferredEnums = new List<MsPdb.LfEnum>();

        public override void VisitClass(MsPdb.LfClass item)
        {
            var sName = item.Name.Value.Trim();
            if (sName.Length < 1) return;

            if (sName.Contains("::"))
            {
                //_deferredClasses.Add(item);
                //return;
                /*
                var parts = sName.Split("::").GetEnumerator();
                if (!parts.MoveNext()) { throw new InvalidDataException(); }
                var cur = new TypeSpec((string)parts.Current, item);
                var root = cur;
                while (parts.MoveNext())
                {
                    var next = new TypeSpec((string)parts.Current, item);
                    cur.AddType(next);
                    cur = next;
                }
                sName.ToString();
                */
            }

            if (item.Properties.IsNested)
            {

            }

            if (sName.Contains("::"))
            {
                //Console.WriteLine(item.Properties.IsNested);
                // $TODO
                return;
            }

            var template = Regex.Match(sName, @"(.*)<(.*)>");
            if (template.Success)
            {
                var sTemplate = template.Groups[1].Value;
                var sTemplateSpec = template.Groups[2].Value;

                if (!handledTemplates.Contains(sTemplate))
                {
                    var templateArgs = sTemplateSpec.Split(',').ToList();
                    var templateSpec = "";

                    var first = true;
                    for (var i = 0; i < templateArgs.Count; i++)
                    {
                        if (first) first = false;
                        else templateSpec += ",";

                        var isNumber = ulong.TryParse(templateArgs[i], out var num);
                        templateSpec += isNumber ? $"long N{i}" : $"typename T{i}";
                    }

                    handledTemplates.Add(sTemplate);
                    _tw.WriteLine($"template<{templateSpec}> class {sTemplate} {{}};");
                }
                _tw.Write("template<> ");
            }

            var derived = item.DerivedType.Type?.Data?.Body;
            if (derived != null)
            {
                VisitType(derived);
            }
            var vshape = item.VshapeType.Type?.Data?.Body;
            if (vshape != null)
            {
                VisitType(vshape);
            }

            var sFinal = item.Properties.Sealed ? "final" : "";
            var fType = item.FieldType.Type?.Data?.Body;

            if (fType != null)
            {
                VisitType(fType);
            }
            _tw.Write("class ");
            if (item.Properties.Packed)
            {
                EmitPacked();
            }
            _tw.Write(sName);
            if (item.Properties.ForwardReference)
            {
                _tw.WriteLine(';');
            } else
            {
                _tw.WriteLine(" {");
                _tw.WriteLine("};");
            }
            _tw.WriteLine();
        }

        public override void VisitFieldList(MsPdb.LfFieldlist item)
        {
            foreach (var f in item.Data)
            {
                VisitType(f.Body);
            }
        }

        public override void VisitEnum(MsPdb.LfEnum item)
        {
            var sName = item.Name.Value;
            if (sName.Contains("::"))
            {
                //_deferredEnums.Add(item);
                //return;
            }

            _tw.Write($"enum {item.Name.Value}");
            var underlyingType = item.UnderlyingType.Type?.Data?.Body;
            if (underlyingType != null)
            {
                _tw.Write(" : ");
                VisitType(underlyingType);
            }
            _tw.WriteLine(" {");
            var fieldType = item.FieldType.Type?.Data?.Body;
            if (fieldType != null)
            {
                if (fieldType is not MsPdb.LfFieldlist fieldlist)
                {
                    throw new NotImplementedException();
                }
                var first = true;
                foreach (var t in fieldlist.Data)
                {
                    if (first) first = false;
                    else _tw.WriteLine(',');

                    var data = t.Body;
                    if (data is not MsPdb.LfEnumerate enumerate)
                    {
                        throw new InvalidDataException();
                    }
                    _tw.Write($"{enumerate.FieldName} = ");
                    VisitNumericType(enumerate.Value);
                }
                _tw.WriteLine();
            }
            _tw.WriteLine("};");
        }

        public void VisitNumericType(MsPdb.CvNumericType item)
        {
            switch (item.Value)
            {
                case int v:
                    _tw.Write(v);
                    break;
                case ushort v:
                    _tw.Write(v);
                    break;
                case sbyte v:
                    _tw.Write(v);
                    break;
                case uint v:
                    _tw.Write(v);
                    break;
                case MsPdb.CvNumericLiteral i:
                    _tw.Write(i.Value);
                    break;
                default:
                    throw new NotImplementedException(item.Value.GetType().FullName);
            }
        }

        public override void VisitEnumerate(MsPdb.LfEnumerate item)
        {

        }

        public override void VisitUnion(MsPdb.LfUnion item)
        {
            var fields = item.Field.Type?.Data?.Body;
            if (fields != null)
            {
                VisitType(fields);
            }
        }

        public void VisitVtshape(MsPdb.LfVtshape item)
        {
            foreach (var descr in item.Descriptors)
            {
            }
        }

        public PdbHeaderGenerator(MsPdb pdb, TextWriter tw)
        {
            _pdb = pdb;
            _tw = tw;
        }

        public void Generate()
        {
            foreach (var t in _pdb.TpiStream.Types.Types.Select(t => t.Data.Body))
            {
                VisitType(t);
            }
        }
    }
}
