meta:
  id: pdb
  file-extension: pdb
  endian: le
  ks-opaque-types: true

types:
  pdb_signature:
    seq:
      - id: magic
        type: str
        terminator: 0x1A
        encoding: UTF-8
      - id: id
        type: str
        size: 2
        encoding: UTF-8
  get_num_pages:
    params:
      - id: num_bytes
        type: u4
    instances:
      num_pages:
        value: (num_bytes + _root.page_size - 1) / _root.page_size
  pdb_header_ds:
    seq:
      - size: 3
      - id: page_size
        type: u4
      - id: fpm_page_number
        type: u4
      - id: num_pages
        type: u4
      - id: directory_size
        type: u4
      - id: page_map
        type: u4
    instances:
      zzz_num_stream_table_pages:
        type: get_num_pages(directory_size)
      # number of pages required for the stream table
      num_stream_table_pages:
        value: zzz_num_stream_table_pages.num_pages
      stream_table_page_list_size:
        value:
          num_stream_table_pages * sizeof<u4>
      zzz_num_stream_table_pagelist_pages:
        type: get_num_pages(stream_table_page_list_size)
      # number of pages required for the list of pages (u4 * num_pages)
      num_stream_table_pagelist_pages:
        value: zzz_num_stream_table_pagelist_pages.num_pages
  pdb_page:
    seq:
      - id: data
        size: _root.page_size
  # represents a PDB page number
  # offers a helper to fetch the page data
  pdb_page_number:
    seq:
      - id: page_number
        type: u4
    instances:
      page:
        io: _root._io
        pos: _root.page_size * page_number
        type: pdb_page
  # represents a contiguous array of PDB page numbers
  pdb_page_number_list:
    params:
      - id: num_pages
        type: u4
    seq:
      - id: pages
        repeat: expr
        repeat-expr: num_pages
        type: pdb_page_number
  # represents a contiguous array of PDB pages
  pdb_pagelist:
    params:
      - id: num_pages
        type: u4
    seq:
      - id: page
        type: pdb_page
        size: _root.page_size
        repeat: expr
        repeat-expr: num_pages
  pdb_stream_ref:
    seq:
      - id: stream_number
        type: s2
    instances:
      size:
        if: stream_number > -1 and stream_number < _root.stream_table.num_streams
        value: _root.stream_table.stream_sizes[stream_number].stream_size
      data:
        if: stream_number > -1 and stream_number < _root.stream_table.num_streams
        value: _root.stream_table.streams[stream_number].data
  pdb_stream_entry:
    params:
      - id: stream_number
        type: u4
    seq:
      - id: stream_size
        type: u4
    instances:
      zzz_num_directory_pages:
        type: get_num_pages(stream_size)
      num_directory_pages:
        value: zzz_num_directory_pages.num_pages
  pdb_stream_data:
    params:
      - id: stream_size
        type: u4
    seq:
      - id: data
        size: stream_size
  pdb_stream_pagelist:
    params:
      - id: stream_number
        type: u4
    seq:
      - id: pages
        type: pdb_page_number_list(num_directory_pages)
    instances:
      stream_size:
        value: _parent.stream_sizes[stream_number].stream_size
      data:
        value: zzz_pages.data
      zzz_pages:
        size: 0
        process: concat_pages(pages.pages)
        type: pdb_stream_data(stream_size)
      num_directory_pages:
        value: _parent.stream_sizes[stream_number].num_directory_pages
  pdb_stream_table:
    seq:
      - id: num_streams
        type: u4
      - id: stream_sizes
        if: _root.pdb_type == pdb_type::big
        type: pdb_stream_entry(_index)
        repeat: expr
        repeat-expr: num_streams
      - id: streams
        type: pdb_stream_pagelist(_index)
        repeat: expr
        repeat-expr: num_streams
  dbi_header_old:
    seq:
      - id: gs_symbols_stream
        type: pdb_stream_ref
      - id: ps_symbols_stream
        type: pdb_stream_ref
      - id: symbol_records_stream
        type: pdb_stream_ref
      - id: module_list_size
        type: u4
      - id: section_contribution_size
        type: u4
      - id: section_map_size
        type: u4
  ti_offset:
    params:
      - id: index
        type: u4
    seq:
      - id: type_index
        type: u4
      - id: offset
        type: u4
    instances:
      #types:
      #  io: _root.pdb_ds.tpi.types._io
      #  pos: offset
      #  type: tpi_tioff_block_reader(type_index, block_length)
      has_next_block:
        value: index + 1 < _parent.num_items
      next_block:
        if: has_next_block
        value: _parent.items[index+1]
      block_end:
        value: has_next_block == true
          ? next_block.type_index
          : _root.pdb_ds.tpi.header.max_type_index
      block_length:
        value: block_end - type_index
  ti_offset_list:
    seq:
      - id: invoke_items_start
        size: 0
        if: items_start >= 0
      - id: items
        type: ti_offset(_index)
        repeat: eos
      - id: invoke_items_end
        size: 0
        if: items_end >= 0
    instances:
      items_start:
        value: _io.pos
      items_end:
        value: _io.pos
      num_items:
        value: (items_end - items_start) / sizeof<ti_offset>
  tpi_slice:
    seq:
      - id: offset
        type: u4
      - id: size
        type: u4
    instances:
      data:
        io: _parent._io
        pos: offset
        size: size
  tpi_hash_data:
    instances:
      hash_values:
        pos: _parent.hash_values_slice.offset
        size: _parent.hash_values_slice.size
      ti_offset_list:
        type: ti_offset_list
        pos: _parent.type_offsets_slice.offset
        size: _parent.type_offsets_slice.size
      hash_head_list:
        pos: _parent.hash_head_list_slice.offset
        size: _parent.hash_head_list_slice.size
  tpi_hash:
    seq:
      - id: hash_stream
        type: pdb_stream_ref
      - id: aux_hash_stream
        type: pdb_stream_ref
      - id: hash_key_size
        type: u4
      - id: num_hash_buckets
        type: u4
      - id: hash_values_slice
        type: tpi_slice
      - id: type_offsets_slice
        type: tpi_slice
      - id: hash_head_list_slice
        type: tpi_slice
    instances:
      tpi_hash_data:
        size: 0
        process: cat(hash_stream.data)
        type: tpi_hash_data
  tpi_header:
    enums:
      version:
        19950410: v40
        19951122: v41
        19960307: v50_beta
        19961031: v50
        19990903: v70
        20040203: v80
    seq:
      - id: version
        type: u4
        enum: version
      - id: header_size
        type: u4
      - id: min_type_index
        type: u4
      - id: max_type_index
        type: u4
      - id: gp_rec_size
        type: u4
      - id: hash
        type: tpi_hash
  tpi_numeric_literal:
    params:
      - id: value
        type: u2
  lf_char:
    seq:
      - id: value
        type: s1
  tpi_numeric_type:
    seq:
      - id: type
        type: u2
        enum: tpi::leaf_type
      - id: value
        type:
          switch-on: type
          cases:
            tpi::leaf_type::lf_char: s1
            tpi::leaf_type::lf_short: s2
            tpi::leaf_type::lf_ushort: u2
            tpi::leaf_type::lf_long: s4
            tpi::leaf_type::lf_ulong: u4
            tpi::leaf_type::lf_quadword: s8
            tpi::leaf_type::lf_uquadword: u8
            _: tpi_numeric_literal(value.as<u2>)
  tpi_type_ref:
    seq:
      - id: index
        type: u4
    instances:
      array_index:
        value: index - _root.pdb_ds.tpi.header.min_type_index
      type:
        value: _root.pdb_ds.tpi.types.types[array_index]
  lf_enum:
    seq:
      - id: num_elements
        type: u2
      - id: type_properties
        type: u2
      - id: underlying_type
        type: tpi_type_ref
      - id: field_type
        type: tpi_type_ref
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
  lf_enumerate:
    seq:
      - id: attributes
        type: u2
      - id: value
        type: tpi_numeric_type
      - id: field_name
        type: str
        encoding: UTF-8
        terminator: 0
  lf_fieldlist:
    seq:
      - id: fields
        type: tpi_type_data(true)
        repeat: eos
  lf_array:
    seq:
      - id: element_type
        type: tpi_type_ref
      - id: indexing_type
        type: tpi_type_ref
      - id: size
        type: tpi_numeric_type
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
  lf_class:
    seq:
      - id: number_of_elements
        type: u2
      - id: field_properties
        type: u2
      - id: field_type
        type: tpi_type_ref
      - id: derived_type
        type: tpi_type_ref
      - id: vshape_type
        type: tpi_type_ref
      - id: struct_size
        type: tpi_numeric_type
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
  lf_pointer:
    seq:
      - id: underlying_type
        type: tpi_type_ref
      - id: attributes
        type: u4
  lf_member:
    seq:
      - id: attributes
        type: u2
      - id: field_type
        type: tpi_type_ref
      - id: offset
        type: tpi_numeric_type
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
  lf_procedure:
    enums:
      calling_convention:
        0: near_c
        1: far_c
        2: near_pascal
        3: far_pascal
        4: near_fast
        5: far_fast
        # 6: unused
        7: near_std
        8: far_std
        9: near_sys
        0xa: far_sys
        0xb: thiscall
        0xc: mipscall
        0xd: generic
        0xe: alphacall
        0xf: ppccall
        0x10: shcall
        0x11: armcall
        0x12: am33call
        0x13: tricall
        0x14: sh5call
        0x15: mr32call
        0x16: clrcall
        0x17: inline
        0x18: near_vector
        # 0x19: reserved
    seq:
      - id: return_value_type
        type: tpi_type_ref
      - id: calling_convention
        type: u1
        enum: calling_convention
  tpi_type_data:
    params:
      - id: nested
        type: bool
    seq:
      - id: type
        type: u2
        enum: tpi::leaf_type
      - id: body
        type: 
          switch-on: type
          cases:
            tpi::leaf_type::lf_enumerate: lf_enumerate
            tpi::leaf_type::lf_enum: lf_enum
            tpi::leaf_type::lf_fieldlist: lf_fieldlist
            tpi::leaf_type::lf_pointer: lf_pointer
            tpi::leaf_type::lf_class: lf_class
            tpi::leaf_type::lf_structure: lf_class
            tpi::leaf_type::lf_array: lf_array
            tpi::leaf_type::lf_procedure: lf_procedure
            tpi::leaf_type::lf_member: lf_member
      - id: invoke_end_body
        if: end_body_pos >= 0
        size: 0
      - id: remaining
        if: nested == false
        #size: padding_size
        size-eos: true
      - id: padding
        if: nested == true
        size: padding_size
    instances:
      trailing_byte:
        if: end_body_pos < _io.size
        pos: end_body_pos
        type: u1
      has_padding:
        value: trailing_byte >= tpi::leaf_type::lf_pad1.as<u1>
          and trailing_byte <= tpi::leaf_type::lf_pad15.as<u1>
      padding_size:
        value: has_padding ? trailing_byte & 0xF : 0
      end_body_pos:
        value: _io.pos
  tpi_type_ds:
    params:
      - id: ti
        type: u4
    seq:
      - id: length
        type: u2
      - id: invoke_data_pos
        if: data_pos >= 0
        size: 0
    instances:
      data_pos:
        value: _io.pos
      # lazy instance
      data:
        pos: data_pos
        size: length
        type: tpi_type_data(false)
        if: length > 0
  tpi_types:
    seq:
      - id: types
        type: tpi_type_ds(_root.pdb_ds.tpi.header.min_type_index + _index)
        repeat: eos
        #repeat: expr
        #repeat-expr: 100
  tpi:
    enums:
      leaf_type:
        0x0001: lf_modifier_16t
        0x0002: lf_pointer_16t
        0x0003: lf_array_16t
        0x0004: lf_class_16t
        0x0005: lf_structure_16t
        0x0006: lf_union_16t
        0x0007: lf_enum_16t
        0x0008: lf_procedure_16t
        0x0009: lf_mfunction_16t
        0x000a: lf_vtshape
        0x000b: lf_cobol0_16t
        0x000c: lf_cobol1
        0x000d: lf_barray_16t
        0x000e: lf_label
        0x000f: lf_null
        0x0010: lf_nottran
        0x0011: lf_dimarray_16t
        0x0012: lf_vftpath_16t
        0x0013: lf_precomp_16t
        0x0014: lf_endprecomp
        0x0015: lf_oem_16t
        0x0016: lf_typeserver_st
        0x0200: lf_skip_16t
        0x0201: lf_arglist_16t
        0x0202: lf_defarg_16t
        0x0203: lf_list
        0x0204: lf_fieldlist_16t
        0x0205: lf_derived_16t
        0x0206: lf_bitfield_16t
        0x0207: lf_methodlist_16t
        0x0208: lf_dimconu_16t
        0x0209: lf_dimconlu_16t
        0x020a: lf_dimvaru_16t
        0x020b: lf_dimvarlu_16t
        0x020c: lf_refsym
        0x0400: lf_bclass_16t
        0x0401: lf_vbclass_16t
        0x0402: lf_ivbclass_16t
        0x0403: lf_enumerate_st
        0x0404: lf_friendfcn_16t
        0x0405: lf_index_16t
        0x0406: lf_member_16t
        0x0407: lf_stmember_16t
        0x0408: lf_method_16t
        0x0409: lf_nesttype_16t
        0x040a: lf_vfunctab_16t
        0x040b: lf_friendcls_16t
        0x040c: lf_onemethod_16t
        0x040d: lf_vfuncoff_16t
        0x040e: lf_nesttypeex_16t
        0x040f: lf_membermodify_16t
        0x1000: lf_ti16_max
        0x1001: lf_modifier
        0x1002: lf_pointer
        0x1003: lf_array_st
        0x1004: lf_class_st
        0x1005: lf_structure_st
        0x1006: lf_union_st
        0x1007: lf_enum_st
        0x1008: lf_procedure
        0x1009: lf_mfunction
        0x100a: lf_cobol0
        0x100b: lf_barray
        0x100c: lf_dimarray_st
        0x100d: lf_vftpath
        0x100e: lf_precomp_st
        0x100f: lf_oem
        0x1010: lf_alias_st
        0x1011: lf_oem2
        0x1200: lf_skip
        0x1201: lf_arglist
        0x1202: lf_defarg_st
        0x1203: lf_fieldlist
        0x1204: lf_derived
        0x1205: lf_bitfield
        0x1206: lf_methodlist
        0x1207: lf_dimconu
        0x1208: lf_dimconlu
        0x1209: lf_dimvaru
        0x120a: lf_dimvarlu
        0x1400: lf_bclass
        0x1401: lf_vbclass
        0x1402: lf_ivbclass
        0x1403: lf_friendfcn_st
        0x1404: lf_index
        0x1405: lf_member_st
        0x1406: lf_stmember_st
        0x1407: lf_method_st
        0x1408: lf_nesttype_st
        0x1409: lf_vfunctab
        0x140a: lf_friendcls
        0x140b: lf_onemethod_st
        0x140c: lf_vfuncoff
        0x140d: lf_nesttypeex_st
        0x140e: lf_membermodify_st
        0x140f: lf_managed_st
        0x1501: lf_typeserver
        0x1502: lf_enumerate
        0x1503: lf_array
        0x1504: lf_class
        0x1505: lf_structure
        0x1506: lf_union
        0x1507: lf_enum
        0x1508: lf_dimarray
        0x1509: lf_precomp
        0x150a: lf_alias
        0x150b: lf_defarg
        0x150c: lf_friendfcn
        0x150d: lf_member
        0x150e: lf_stmember
        0x150f: lf_method
        0x1510: lf_nesttype
        0x1511: lf_onemethod
        0x1512: lf_nesttypeex
        0x1513: lf_membermodify
        0x1514: lf_managed
        0x1515: lf_typeserver2
        0x1516: lf_strided_array
        0x1517: lf_hlsl
        0x1518: lf_modifier_ex
        0x1519: lf_interface
        0x151a: lf_binterface
        0x151b: lf_vector
        0x151c: lf_matrix
        0x151d: lf_vftable
        0x1601: lf_func_id
        0x1602: lf_mfunc_id
        0x1603: lf_buildinfo
        0x1604: lf_substr_list
        0x1605: lf_string_id
        0x1606: lf_udt_src_line
        0x1607: lf_udt_mod_src_line
        0x8000: lf_char
        0x8001: lf_short
        0x8002: lf_ushort
        0x8003: lf_long
        0x8004: lf_ulong
        0x8005: lf_real32
        0x8006: lf_real64
        0x8007: lf_real80
        0x8008: lf_real128
        0x8009: lf_quadword
        0x800a: lf_uquadword
        0x800b: lf_real48
        0x800c: lf_complex32
        0x800d: lf_complex64
        0x800e: lf_complex80
        0x800f: lf_complex128
        0x8010: lf_varstring
        0x8017: lf_octword
        0x8018: lf_uoctword
        0x8019: lf_decimal
        0x801a: lf_date
        0x801b: lf_utf8string
        0x801c: lf_real16
        0xf0: lf_pad0
        0xf1: lf_pad1
        0xf2: lf_pad2
        0xf3: lf_pad3
        0xf4: lf_pad4
        0xf5: lf_pad5
        0xf6: lf_pad6
        0xf7: lf_pad7
        0xf8: lf_pad8
        0xf9: lf_pad9
        0xfa: lf_pad10
        0xfb: lf_pad11
        0xfc: lf_pad12
        0xfd: lf_pad13
        0xfe: lf_pad14
        0xff: lf_pad15
    seq:
      - id: header
        type: tpi_header
      - id: types
        type: tpi_types
        size-eos: true
  dbi_header_new:
    enums:
      version:
        930803: v41
        19960307: v50
        19970606: v60
        19990903: v70
        20091201: v110
    seq:
      - id: signature
        type: u4
      - id: version
        type: u4
        enum: version
      - id: age
        type: u4
      - id: gs_symbols_stream
        type: pdb_stream_ref
      - id: internal_version
        type: u2
      - id: ps_symbols_stream
        type: pdb_stream_ref
      - id: pdb_dll_version
        type: u2
      - id: symbol_records_stream
        type: pdb_stream_ref
      - id: rbld_version
        type: u2
      - id: module_list_size
        type: u4
      - id: section_contribution_size
        type: u4
      - id: section_map_size
        type: u4
      - id: file_info_size
        type: u4
      - id: type_server_map_size
        type: u4
      - id: mfc_type_server_index
        type: u4
      - id: debug_header_size
        type: u4
      - id: ec_substream_size
        type: u4
      - id: flags
        type: u2
      - id: machine_type
        type: u2
      - id: reserved
        type: u4
  section_contrib40:
    seq:
      - id: section_index
        type: u2
      - id: pad0
        type: u2
      - id: offset
        type: u4
      - id: size
        type: u4
      - id: characteristics
        type: u4
      - id: module_index
        type: u2
      - id: pad1
        type: u2
  section_contrib:
    seq:
      - id: base
        type: section_contrib40
      - id: data_crc
        type: u4
      - id: reloc_crc
        type: u4
  section_contrib2:
    seq:
      - id: base
        type: section_contrib
      - id: coff_section_index
        type: u4
  ec_info:
    seq:
      - id: src_filename_index
        type: u4
      - id: pdb_filename_index
        type: u4
  align:
    params:
      - id: value
        type: u4
      - id: alignment
        type: u4
    instances:
      aligned:
        value: (value + alignment - 1) & ((alignment - 1) ^ -1)
  module_info:
    seq:
      - id: invoke_position_start
        size: 0
        if: position_start >= 0
      - id: open_module_handle
        type: u4
      - id: section_contribution
        type: section_contrib
      - id: flags
        type: u2
      - id: stream
        type: pdb_stream_ref
      - id: symbols_size
        type: u4
      - id: lines_size
        type: u4
      - id: c13_lines_size
        type: u4
      - id: number_of_files
        type: u2
      - id: pad0
        type: u2
      - id: file_names_offsets
        type: u4
      - id: ec_info
        if: _root.pdb_type == pdb_type::big
        type: ec_info
      - id: module_name
        type: str
        encoding: UTF-8
        terminator: 0
      - id: object_filename
        type: str
        encoding: UTF-8
        terminator: 0
      - id: invoke_position_end
        size: 0
        if: position_end >= 0
      - id: padding
        size: padding_size
    instances:
      padding_size:
        value: alignment.aligned - position_end
      alignment:
        type: align(position_end, 4)
      position_start:
        value: _io.pos
      position_end:
        value: _io.pos
  module_list:
    seq:
      - id: modules
        type: module_info
        repeat: eos
  section_contribution_list:
    enums:
      version_type:
        # 0xeffe0000 + 19970605
        0xF12EBA2D: v60
        # 0xeffe0000 + 20140516
        0xF13151E4: new
    seq:
      - id: version
        type: u4
        enum: version_type
      - id: items
        repeat: eos
        type:
          switch-on: version
          cases:
            version_type::v60: section_contrib
            version_type::new: section_contrib2
    instances:
      item_size:
        value: version == version_type::new
          ? sizeof<section_contrib2> : version == version_type::v60
          ? sizeof<section_contrib> : sizeof<section_contrib40>
  omf_segment_map:
    seq:
      - id: num_segments
        type: u2
      - id: num_logical_segments
        type: u2
      - id: segments
        type: omf_segment_map_descriptor
        repeat: expr
        repeat-expr: num_segments
  omf_segment_map_descriptor:
    seq:
      - id: flags
        type: u2
        doc: descriptor flags bit field.
      - id: overlay_number
        type: u2
        doc: the logical overlay number
      - id: group_index
        type: u2
        doc: group index into the descriptor array
      - id: segment_index
        type: u2
        doc: logical segment index - interpreted via flags
      - id: segment_name_index
        type: u2
        doc: segment or group name - index into sstSegName
      - id: class_name_index
        type: u2
        doc: class name - index into sstSegName
      - id: offset
        type: u4
        doc: byte offset of the logical within the physical segment
      - id: size
        type: u4
        doc: byte count of the logical segment or group
  file_info_string:
    seq:
      - id: chars_index
        type: u4
    instances:
      string:
        pos: _parent.strings_start + chars_index
        type: str
        encoding: UTF-8
        terminator: 0
  file_info:
    seq:
      - id: num_modules
        type: u2
      - id: num_references
        type: u2
      - id: module_to_reference
        type: u2
        repeat: expr
        repeat-expr: num_modules
      - id: reference_to_file_index
        type: u2
        repeat: expr
        repeat-expr: num_modules
      - id: filename_indices
        type: file_info_string
        repeat: expr
        repeat-expr: num_references
      - id: invoke_strings_start
        size: 0
        if: strings_start >= 0
    instances:
      strings_start:
        value: _io.pos
  type_server_map:
    seq:
      - id: reserved_typemap_handle
        type: u4
      - id: ti_base
        type: s4
      # LF_TYPESERVER body
      - id: signature
        type: u4
      - id: age
        type: u4
      - id: pdb_path_name
        type: str
        encoding: UTF-8
        terminator: 0
      - id: invoke_position_end
        size: 0
        if: position_end >= 0
      - id: padding
        size: padding_size
    instances:
      padding_size:
        value: alignment.aligned - position_end
      alignment:
        type: align(position_end, 4)
      position_end:
        value: _io.pos
  type_server_map_list:
    seq:
      - id: items
        type: type_server_map
        repeat: eos
  array:
    params:
      - id: element_size
        type: u4
    seq:
      - id: num_elements
        type: u4
      - id: data
        size: element_size * num_elements
      #- id: elements
      #  type:
      #    switch-on: element_size
      #    cases:
      #      1: u1
      #      2: u2
      #      4: u4
      #      8: u8
      #  repeat: expr
      #  repeat-expr: num_elements
  buffer:
    seq:
      - id: num_bytes
        type: u4
      - id: invoke_data_start
        size: 0
        if: data_start >= 0
      - id: data
        size: num_bytes
    instances:
      data_start:
        value: _io.pos
  name_table_string:
    seq:
      - id: chars_index
        type: u4
    instances:
      string:
        io: _parent._parent._io
        pos: _parent._parent.buffer.data_start + chars_index
        type: str
        encoding: UTF-8
        terminator: 0
  name_table_strings:
    seq:
      - id: strings
        repeat: eos
        type: name_table_string
  name_table:
    enums:
      version:
        1: hash
        2: hash_v2
    seq:
      - id: magic
        #contents: 0xeffeeffe
        contents: [0xfe, 0xef, 0xfe, 0xef]
      - id: version
        type: u4
        enum: version
      - id: buffer
        type: buffer
      - id: indices
        type: array(4)
      - id: num_names
        type: u4
    instances:
      strings:
        size: 0
        process: cat(indices.data)
        type: name_table_strings
  image_section_header:
    seq:
      - id: name
        size: 8
        type: str
        pad-right: 0
        encoding: UTF-8
      - id: misc
        type: u4
      - id: virtual_address
        type: u4
      - id: size_of_raw_data
        type: u4
      - id: pointer_to_raw_data
        type: u4
      - id: pointer_to_relocations
        type: u4
      - id: pointer_to_line_numbers
        type: u4
      - id: number_of_relocations
        type: u2
      - id: number_of_line_numbers
        type: u2
      - id: characteristics
        type: u4
    instances:
      # TODO: automatic discrimination/if
      physical_address:
        value: misc
      virtual_size:
        value: misc
  debug_section_hdr_stream:
    seq:
      - id: hdr
        type: image_section_header
        repeat: eos
  debug_data:
    seq:
      - id: fpo_stream
        type: pdb_stream_ref
      - id: exception_stream
        type: pdb_stream_ref
      - id: fixup_stream
        type: pdb_stream_ref
      - id: omap_to_src_stream
        type: pdb_stream_ref
      - id: omap_from_src_stream
        type: pdb_stream_ref
      - id: section_hdr_stream
        type: pdb_stream_ref
      - id: token_rid_map_stream
        type: pdb_stream_ref
      - id: xdata_stream
        type: pdb_stream_ref
      - id: pdata_stream
        type: pdb_stream_ref
      - id: new_fpo_stream
        type: pdb_stream_ref
      - id: section_hdr_orig_stream
        type: pdb_stream_ref
    instances:
      section_hdr_stream_data:
        if: section_hdr_stream.stream_number > -1
        size: 0
        process: cat(section_hdr_stream.data)
        type: debug_section_hdr_stream
  dbi:
    seq:
      - id: header_old
        if: signature != -1
        type: dbi_header_old
      - id: header_new
        if: signature == -1
        type: dbi_header_new
      - id: modules
        size: header_new.module_list_size
        if: header_new.module_list_size > 0
        type: module_list
      - id: section_contributions
        size: header_new.section_contribution_size
        if: header_new.section_contribution_size > 0
        type: section_contribution_list
      - id: section_map
        size: header_new.section_map_size
        if: header_new.section_map_size > 0
        type: omf_segment_map
      - id: file_info
        size: header_new.file_info_size
        if: header_new.file_info_size > 0
        type: file_info
      - id: type_server_map
        size: header_new.type_server_map_size
        if: header_new.type_server_map_size > 0
        type: type_server_map
      - id: ec_info
        size: header_new.ec_substream_size
        if: header_new.ec_substream_size > 0
        type: name_table
      - id: debug_data
        size: header_new.debug_header_size
        if: header_new.debug_header_size > 0
        type: debug_data
    instances:
      # invalid gs/ps syms marker for DBI old/new detection
      signature:
        pos: 0
        type: s4
  pdb_ds:
    seq:
      - id: header
        type: pdb_header_ds
      - id: stream_table_root_pagelist_data
        type: pdb_pagelist(header.num_stream_table_pagelist_pages)
        size: header.page_size * header.num_stream_table_pagelist_pages
    instances:
      # holds page numbers for the directory page list
      stream_table_root_pages:
        io: stream_table_root_pagelist_data._io
        pos: 0
        type: pdb_page_number
        repeat: expr
        repeat-expr: header.num_stream_table_pagelist_pages
      # holds page numbers for the stream table
      stream_table_pages:
        size: 0
        process: concat_pages(stream_table_root_pages)
        type: pdb_page_number_list(header.num_stream_table_pages)
      stream_table:
        size: 0
        process: concat_pages(stream_table_pages.pages)
        type: pdb_stream_table
      tpi:
        size: 0
        type: tpi
        process: cat(stream_table.streams[default_stream::tpi.as<u4>].data)
      dbi:
        size: 0
        type: dbi
        process: cat(stream_table.streams[default_stream::dbi.as<u4>].data)
  si_persist_ds:
    seq:
      - id: num_bytes
        type: u4
  si_persist_jg:
    seq:
      - id: num_bytes
        type: u4
      - id: map_pagenum
        type: u4
seq:
  - id: signature
    type: pdb_signature
  - id: pdb_ds
    if: signature.id == "DS"
    type: pdb_ds
instances:
  page_size:
    value: pdb_ds.header.page_size
  pdb_type:
    value: _root.signature.id == "DS" ? pdb_type::big : 
      _root.signature.id == "JG" ? pdb_type::small : pdb_type::old
  si_persist_size:
    value: pdb_type == pdb_type::big ? sizeof<si_persist_ds>
      : pdb_type == pdb_type::small ? sizeof<si_persist_jg>
      : 0
  stream_table:
    value: pdb_ds.stream_table
enums:
  # pseudo-enum to keep track of the PDB type
  pdb_type:
    0: old
    1: small
    2: big
  default_stream:
    1: pdb
    2: tpi
    3: dbi
    4: ipi
  