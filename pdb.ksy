meta:
  id: pdb
  file-extension: pdb
  endian: le
  bit-endian: le
  ks-opaque-types: true

types:
  pdb_signature:
    seq:
      - id: magic
        type: str
        terminator: 0x1A
        encoding: UTF-8
      - id: invoke_id_pos
        size: 0
        if: id_pos >= 0
      - id: id
        type: str
        size: 2
        encoding: UTF-8
    instances:
      version_major_pos:
        value: id_pos - 7
      version_major:
        value: magic.substring(version_major_pos, version_major_pos + 1)
      id_pos:
        value: _io.pos
  get_num_pages:
    params:
      - id: num_bytes
        type: u4
    instances:
      num_pages:
        value: (num_bytes + _root.page_size - 1) / _root.page_size

  # only used from the DS Constructor to avoid _root references and break the cycle
  get_num_pages2:
    params:
      - id: num_bytes
        type: u4
      - id: page_size
        type: u4
    instances:
      num_pages:
        value: (num_bytes + page_size - 1) / page_size

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
  pdb_page:
    seq:
      - id: data
        size: _root.page_size
  pdb_page2:
    params:
      - id: page_size
        type: u4
    seq:
      - id: data
        size: page_size 
  # represents a PDB page number
  # offers a helper to fetch the page data
  pdb_page_number:
    seq:
      - id: page_number_data
        type:
          switch-on: _root.page_number_size
          cases:
            2: u2
            4: u4
    instances:
      page_number:
        value: page_number_data.as<u4>
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
      - id: page_size
        type: u4
    seq:
      - id: page
        type: pdb_page2(page_size)
        size: page_size
        repeat: expr
        repeat-expr: num_pages
  pdb_stream_ref:
    seq:
      - id: stream_number
        type: s2
    instances:
      # checks if the stream number is not snNil, and it's within bounds
      is_valid_stream:
        value: stream_number > -1 and stream_number < _root.num_streams
      zzz_size:
        if: is_valid_stream
        type: get_stream_size(stream_number)
      size:
        value: 'is_valid_stream ? zzz_size.value : 0'
      zzz_data:
        if: is_valid_stream
        type: get_stream_data(stream_number)
      data:
        if: is_valid_stream
        value: zzz_data.value
  pdb_stream_entry_jg:
    doc: 'SI_PERSIST'
    params:
      - id: stream_number
        type: u4
    seq:
      - id: stream_size
        type: u4
      - id: map_spn_pn
        type: u4
    instances:
      zzz_num_directory_pages:
        type: get_num_pages(stream_size)
      num_directory_pages:
        value: zzz_num_directory_pages.num_pages
  pdb_stream_entry_ds:
    doc: 'SI_PERSIST'
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
      data:
        value: zzz_pages.data
      zzz_pages:
        size: 0
        process: concat_pages(pages.pages)
        type: pdb_stream_data(stream_size)
      zzz_stream_size:
        type: get_stream_size(stream_number)
      num_directory_pages:
        value: '_root.pdb_type == pdb_type::big
          ? _parent.stream_sizes_ds[stream_number].num_directory_pages
          : _parent.stream_sizes_jg[stream_number].num_directory_pages'
      stream_size:
        value: zzz_stream_size.value
  get_stream_num_pages:
    params:
      - id: stream_number
        type: u4
    instances:
      value:
        value: '_root.pdb_type == pdb_type::big
          ? _root.pdb_ds.stream_table.stream_sizes_ds[stream_number].num_directory_pages
          : _root.pdb_jg.stream_table.stream_sizes_jg[stream_number].num_directory_pages'
  get_stream_data:
    params:
      - id: stream_number
        type: u4
    instances:
      value:
        value: '_root.pdb_type == pdb_type::big
          ? _root.pdb_ds.stream_table.streams[stream_number].data
          : _root.pdb_jg.stream_table.streams[stream_number].data'
  get_stream_size:
    params:
      - id: stream_number
        type: u4
    instances:
      value:
        value: '_root.pdb_type == pdb_type::big
          ? _root.pdb_ds.stream_table.stream_sizes_ds[stream_number].stream_size
          : _root.pdb_jg.stream_table.stream_sizes_jg[stream_number].stream_size'
  pdb_stream_table:
    seq:
      - id: num_streams
        type: u4
      - id: stream_sizes_ds
        if: _root.pdb_type == pdb_type::big
        type: pdb_stream_entry_ds(_index)
        repeat: expr
        repeat-expr: num_streams
      - id: stream_sizes_jg
        if: _root.pdb_type == pdb_type::small
        type: pdb_stream_entry_jg(_index)
        repeat: expr
        repeat-expr: num_streams
      - id: streams
        type: pdb_stream_pagelist(_index)
        repeat: expr
        repeat-expr: num_streams
  psgi_header:
    seq:
      - id: sym_hash_size
        type: u4
        doc: 'cbSymHash'
      - id: address_map_size
        type: u4
        doc: 'cbAddrMap'
      - id: num_thunks
        type: u4
        doc: 'nThunks'
      - id: thunk_size
        type: u4
        doc: 'cbSizeOfThunk'
      - id: thunk_table_section_index
        type: u4
        doc: 'isectThunkTable'
      - id: thunk_table_offset
        type: u4
        doc: 'offThunkTable'
      - id: num_sections
        type: u4
        doc: 'nSects'
  public_symbols_stream:
    seq:
      - id: header
        type: psgi_header
      - id: symbols_hash_map
        size: header.sym_hash_size
      - id: address_map
        size: header.address_map_size
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
    instances:
      ps_symbols_data:
        size: 0
        if: ps_symbols_stream.stream_number > -1
        process: cat(ps_symbols_stream.data)
        type: public_symbols_stream
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
        value: 'has_next_block == true ? next_block.type_index : _root.tpi.header.max_type_index'
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
        doc: 'main hash stream'
      - id: aux_hash_stream
        type: pdb_stream_ref
        doc: 'auxilliary hash data if necessary'
      - id: hash_key_size
        type: u4
        doc: 'size of hash key'
      - id: num_hash_buckets
        type: u4
        doc: 'how many buckets we have'
      - id: hash_values_slice
        type: tpi_slice
        doc: 'offcb of hashvals'
      - id: type_offsets_slice
        type: tpi_slice
        doc: 'offcb of (TI,OFF) pairs'
      - id: hash_head_list_slice
        type: tpi_slice
        doc: 'offcb of hash head list, maps (hashval,ti), where ti is the head of the hashval chain.'
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
        doc: 'version which created this TypeServer'
      - id: header_size
        type: u4
        doc: 'size of the header, allows easier upgrading and backwards compatibility'
      - id: min_type_index
        type: u4
        doc: 'lowest TI'
      - id: max_type_index
        type: u4
        doc: 'highest TI + 1'
      - id: gp_rec_size
        type: u4
        doc: 'count of bytes used by the gprec which follows.'
      - id: hash
        type: tpi_hash
        doc: 'hash stream schema'
  cv_numeric_literal:
    params:
      - id: value
        type: u2
  lf_char:
    seq:
      - id: value
        type: s1
  cv_properties:
    seq:
      - id: packed
        type: b1
        doc: 'true if structure is packed'
      - id: ctor
        type: b1
        doc: 'true if constructors or destructors present'
      - id: overlapped_operators
        type: b1
        doc: 'true if overloaded operators present'
      - id: is_nested
        type: b1
        doc: 'true if this is a nested class'
      - id: contains_nested
        type: b1
        doc: 'true if this class contains nested types'
      - id: overlapped_assignment
        type: b1
        doc: 'true if overloaded assignment (=)'
      - id: casting_methods
        type: b1
        doc: 'true if casting methods'
      - id: forward_reference
        type: b1
        doc: 'true if forward reference (incomplete defn)'
      - id: scoped_definition
        type: b1
        doc: 'scoped definition'
      - id: has_unique_name
        type: b1
        doc: 'true if there is a decorated name following the regular name'
      - id: sealed
        type: b1
        doc: 'true if class cannot be used as a base class'
      - id: hfa
        type: b2
        enum: tpi::cv_hfa
      - id: intrinsic
        type: b1
        doc: 'true if class is an intrinsic type (e.g. __m128d)'
      - id: mocom
        type: b2
        enum: tpi::cv_mocom_udt
  cv_proc_flags:
    seq:
      - id: nofpo
        type: b1
        doc: 'frame pointer present'
      - id: interrupt
        type: b1
        doc: 'interrupt return'
      - id: far_return
        type: b1
        doc: 'far return'
      - id: never
        type: b1
        doc: 'function does not return'
      - id: not_reached
        type: b1
        doc: 'label isn''t fallen into'
      - id: cust_call
        type: b1
        doc: 'custom calling convention'
      - id: no_inline
        type: b1
        doc: 'function marked as noinline'
      - id: opt_debug_info
        type: b1
        doc: 'function has debug information for optimized code'
  cv_func_attributes:
    seq:
      - id: cxx_return_udt
        type: b1
        doc: 'true if C++ style ReturnUDT'
      - id: is_constructor
        type: b1
        doc: 'true if func is an instance constructor'
      - id: is_virtual_constructor
        type: b1
        doc: 'true if func is an instance constructor of a class with virtual bases'
      - type: b5
  cv_field_attributes:
    seq:
      - id: access_protection
        type: b2
        doc: 'access protection'
        enum: tpi::cv_access
      - id: method_properties
        type: b3
        doc: 'method properties'
        enum: tpi::cv_methodprop
      - id: is_pseudo
        type: b1
        doc: 'compiler generated fcn and does not exist'
      - id: no_inherit
        type: b1
        doc: 'true if class cannot be inherited'
      - id: no_construct
        type: b1
        doc: 'true if class cannot be constructed'
      - id: compiler_generated
        type: b1
        doc: 'compiler generated fcn and does exist'
      - id: is_sealed
        type: b1
        doc: 'true if method cannot be overridden'
      - type: b6
  cv_numeric_type:
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
            _: cv_numeric_literal(type.as<u2>)
  tpi_type_ref16:
    seq:
      - id: index
        type: u2
    instances:
      array_index:
        value: index - _root.min_type_index
      type:
        if: array_index >= 0
        value: _root.types[array_index]
  tpi_type_ref:
    seq:
      - id: index
        type: u4
    instances:
      array_index:
        value: index - _root.min_type_index
      type:
        if: array_index >= 0
        value: _root.types[array_index]
  lf_enum:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: num_elements
        type: u2
        doc: 'count of number of elements in class'
      - id: type_properties
        type: cv_properties
        doc: 'property attribute field'
      - id: underlying_type
        type: tpi_type_ref
        doc: 'underlying type of the enum'
      - id: field_type
        type: tpi_type_ref
        doc: 'type index of LF_FIELD descriptor list'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'length prefixed name of enum'
  lf_enumerate:
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'access'
      - id: value
        type: cv_numeric_type
        doc: 'variable length value field'
      - id: field_name
        type: str
        encoding: UTF-8
        terminator: 0
        doc: 'length prefixed name'
  lf_fieldlist_16t:
    seq:
      - id: data
        type: tpi_type_data(true)
        repeat: eos
        doc: 'field list sub lists'
  lf_fieldlist:
    seq:
      - id: data
        type: tpi_type_data(true)
        repeat: eos
        doc: 'field list sub lists'
  lf_arglist:
    seq:
      - id: count
        type: u4
        doc: 'number of arguments'
      - id: arguments
        type: tpi_type_ref
        repeat: expr
        repeat-expr: count
        doc: 'argument types'
  lf_arglist_16t:
    seq:
      - id: count
        type: u2
        doc: 'number of arguments'
      - id: arguments
        type: tpi_type_ref16
        repeat: expr
        repeat-expr: count
        doc: 'argument types'
  lf_bitfield:
    seq: 
      - id: type
        type: tpi_type_ref
        doc: 'type of bitfield'
      - id: length
        type: u1
      - id: position
        type: u1
  lf_array_16t:
    seq:
      - id: element_type
        type: tpi_type_ref16
        doc: 'type index of element type'
      - id: indexing_type
        type: tpi_type_ref16
        doc: 'type index of indexing type'
      - id: size
        type: cv_numeric_type
        doc: 'variable length data specifying size in bytes'
      - id: name
        type: pdb_string(true)
        doc: 'array name'
  lf_array:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: element_type
        type: tpi_type_ref
        doc: 'type index of element type'
      - id: indexing_type
        type: tpi_type_ref
        doc: 'type index of indexing type'
      - id: size
        type: cv_numeric_type
        doc: 'variable length data specifying size in bytes'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'array name'
  pdb_string:
    params:
      - id: is_prefixed
        type: bool
    seq:
      - id: name_length
        if: is_prefixed
        type: u1
      - id: name_prefixed
        if: is_prefixed
        type: str
        encoding: UTF-8
        size: name_length
      - id: name_cstring
        if: not is_prefixed
        type: str
        encoding: UTF-8
        terminator: 0
    instances:
      name:
        value: 'is_prefixed ? name_prefixed : name_cstring'
  lf_class_16t:
    seq:
      - id: number_of_elements
        type: u2
        doc: 'count of number of elements in class'
      - id: field_type
        type: tpi_type_ref16
        doc: 'type index of LF_FIELD descriptor list'
      - id: properties
        type: cv_properties
        doc: 'property attribute field (prop_t)'
      - id: derived_type
        type: tpi_type_ref16
        doc: 'type index of derived from list if not zero'
      - id: vshape_type
        type: tpi_type_ref16
        doc: 'type index of vshape table for this class' 
      - id: struct_size
        type: cv_numeric_type
        doc: 'data describing length of structure in bytes'
      - id: name
        type: pdb_string(true)
        doc: 'class name'
  lf_class:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: number_of_elements
        type: u2
        doc: 'count of number of elements in class'
      - id: properties
        type: cv_properties
        doc: 'property attribute field (prop_t)'
      - id: field_type
        type: tpi_type_ref
        doc: 'type index of LF_FIELD descriptor list'
      - id: derived_type
        type: tpi_type_ref
        doc: 'type index of derived from list if not zero'
      - id: vshape_type
        type: tpi_type_ref
        doc: 'type index of vshape table for this class'
      - id: struct_size
        type: cv_numeric_type
        doc: 'data describing length of structure in bytes'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'class name'
  lf_pointer_attributes_16t:
    seq:
      - id: pointer_type
        type: b5
        doc: 'ordinal specifying pointer type (CV_ptrtype_e)'
        enum: tpi::cv_ptrtype
      - id: pointer_mode
        type: b3
        doc: 'ordinal specifying pointer mode (CV_ptrmode_e)'
        enum: tpi::cv_ptrmode
      - id: is_flat_32
        type: b1
        doc: 'true if 0:32 pointer'
      - id: is_volatile
        type: b1
        doc: 'TRUE if volatile pointer'
      - id: is_const
        type: b1
        doc: 'TRUE if const pointer'
      - id: is_unaligned
        type: b1
        doc: 'TRUE if unaligned pointer'
      - type: b4
  lf_pointer_attributes:
    seq:
      - id: pointer_type
        type: b5
        doc: 'ordinal specifying pointer type (CV_ptrtype_e)'
        enum: tpi::cv_ptrtype
      - id: pointer_mode
        type: b3
        doc: 'ordinal specifying pointer mode (CV_ptrmode_e)'
        enum: tpi::cv_ptrmode
      - id: is_flat_32
        type: b1
        doc: 'true if 0:32 pointer'
      - id: is_volatile
        type: b1
        doc: 'TRUE if volatile pointer'
      - id: is_const
        type: b1
        doc: 'TRUE if const pointer'
      - id: is_unaligned
        type: b1
        doc: 'TRUE if unaligned pointer'
      - id: is_restricted
        type: b1
        doc: 'TRUE if restricted pointer (allow agressive opts)'
      - id: size
        type: b6
        doc: 'size of pointer (in bytes)'
      - id: is_mocom
        type: b1
        doc: 'TRUE if it is a MoCOM pointer (^ or %)'
      - id: is_lref
        type: b1
        doc: 'TRUE if it is this pointer of member function with & ref-qualifier'
      - id: is_rref
        type: b1
        doc: 'TRUE if it is this pointer of member function with && ref-qualifier'
      - type: b10
  lf_pointer:
    seq:
      - id: underlying_type
        type: tpi_type_ref
      - id: attributes
        type: lf_pointer_attributes
  lf_pointer_16t:
    seq:
      - id: attributes
        type: lf_pointer_attributes_16t
      - id: underlying_type
        type: tpi_type_ref16
  lf_member:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'attribute mask'
      - id: field_type
        type: tpi_type_ref
        doc: 'index of type record for field'
      - id: offset
        type: cv_numeric_type
        doc: 'variable length offset of field'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'length prefixed name of field'
  lf_modifier_flags:
    seq:
      - id: const
        type: b1
        doc: 'TRUE if constant'
      - id: volatile
        type: b1
        doc: 'TRUE if volatile'
      - id: unaligned
        type: b1
        doc: 'TRUE if unaligned'
      - type: b13
  lf_modifier_16t:
    seq:
      - id: flags
        type: lf_modifier_flags
        doc: 'modifier attribute modifier_t'
      - id: modified_type
        type: tpi_type_ref16
        doc: 'modified type'
  lf_modifier:
    seq:
      - id: modified_type
        type: tpi_type_ref
        doc: 'modified type'
      - id: flags
        type: lf_modifier_flags
        doc: 'modifier attribute modifier_t'
  lf_mfunction_16t:
    seq:
      - id: return_type
        type: tpi_type_ref16
        doc: 'type index of return value'
      - id: class_type
        type: tpi_type_ref16
        doc: 'type index of containing class'
      - id: this_type
        type: tpi_type_ref16
        doc: 'type index of this pointer (model specific)'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (call_t)'
      - id: attributes
        type: cv_func_attributes
        doc: 'attributes'
      - id: parameters_count
        type: u2
        doc: 'number of parameters'
      - id: argument_list_type
        type: tpi_type_ref16
        doc: 'type index of argument list'
      - id: this_adjuster
        type: u4
        doc: 'this adjuster (long because pad required anyway)'
  lf_mfunction:
    seq:
      - id: return_type
        type: tpi_type_ref
        doc: 'type index of return value'
      - id: class_type
        type: tpi_type_ref
        doc: 'type index of containing class'
      - id: this_type
        type: tpi_type_ref
        doc: 'type index of this pointer (model specific)'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (call_t)'
      - id: attributes
        type: cv_func_attributes
        doc: 'attributes'
      - id: parameters_count
        type: u2
        doc: 'number of parameters'
      - id: argument_list_type
        type: tpi_type_ref
        doc: 'type index of argument list'
      - id: this_adjuster
        type: u4
        doc: 'this adjuster (long because pad required anyway)'
  lf_one_method:
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'method attribute'
      - id: procedure_type
        type: tpi_type_ref
        doc: 'index to type record for procedure'
      - id: vtable_offset
        if: attributes.method_properties == tpi::cv_methodprop::intro
          or attributes.method_properties == tpi::cv_methodprop::pure_intro
        type: u4
        doc: 'offset in vfunctable if intro virtual'
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
        doc: 'length prefixed name of method'
  ml_method_16t:
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'method attribute'
      - id: index_type
        type: tpi_type_ref16
        doc: 'index to type record for procedure'
      - id: vtable_offset
        if: attributes.method_properties == tpi::cv_methodprop::intro
          or attributes.method_properties == tpi::cv_methodprop::pure_intro
        type: u4
        doc: 'offset in vfunctable if intro virtual'
  ml_method:
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'method attribute'
      - size: 2
      - id: index_type
        type: tpi_type_ref
        doc: 'index to type record for procedure'
      - id: vtable_offset
        if: attributes.method_properties == tpi::cv_methodprop::intro
          or attributes.method_properties == tpi::cv_methodprop::pure_intro
        type: u4
        doc: 'offset in vfunctable if intro virtual'
  lf_methodlist_16t:
    seq:
      - id: methods
        type: ml_method_16t
        repeat: eos
  lf_methodlist:
    seq:
      - id: methods
        type: ml_method
        repeat: eos
  lf_procedure_16t:
    seq:
      - id: return_value_type
        type: tpi_type_ref16
        doc: 'type index of return value'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (CV_call_t)'
      - id: function_attributes
        type: cv_func_attributes
        doc: 'attributes'
      - id: parameter_count
        type: u2
        doc: 'number of parameters'
      - id: arglist
        type: tpi_type_ref16
        doc: 'type index of argument list'
  lf_procedure:
    seq:
      - id: return_value_type
        type: tpi_type_ref
        doc: 'type index of return value'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (CV_call_t)'
      - id: function_attributes
        type: cv_func_attributes
        doc: 'attributes'
      - id: parameter_count
        type: u2
        doc: 'number of parameters'
      - id: arglist
        type: tpi_type_ref
        doc: 'type index of argument list'
  lf_vtshape:
    seq:
      - id: count
        type: u2
        doc: 'number of entries in vfunctable'
      - id: descriptors
        type: b4
        enum: tpi::cv_vts_desc
        repeat: expr
        repeat-expr: count
  lf_union:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: count
        type: u2
        doc: 'count of number of elements in class'
      - id: property
        type: cv_properties
        doc: 'property attribute field'
      - id: field
        type: tpi_type_ref
        doc: 'type index of LF_FIELD descriptor list'
      - id: length
        type: cv_numeric_type
        doc: 'variable length data describing length of structure'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'array name'
  sym_unknown:
    seq:
      - id: data
        size-eos: true
  lf_unknown:
    seq:
      - id: data
        size-eos: true
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
            tpi::leaf_type::lf_enum: lf_enum(false)
            tpi::leaf_type::lf_enum_st: lf_enum(true)
            tpi::leaf_type::lf_fieldlist: lf_fieldlist
            tpi::leaf_type::lf_fieldlist_16t: lf_fieldlist_16t
            tpi::leaf_type::lf_pointer: lf_pointer
            tpi::leaf_type::lf_pointer_16t: lf_pointer_16t
            tpi::leaf_type::lf_class: lf_class(false)
            tpi::leaf_type::lf_class_16t: lf_class_16t
            tpi::leaf_type::lf_class_st: lf_class(true)
            tpi::leaf_type::lf_structure: lf_class(false)
            tpi::leaf_type::lf_structure_st: lf_class(true)
            tpi::leaf_type::lf_structure_16t: lf_class_16t
            tpi::leaf_type::lf_array: lf_array(false)
            tpi::leaf_type::lf_array_st: lf_array(true)
            tpi::leaf_type::lf_array_16t: lf_array_16t
            tpi::leaf_type::lf_procedure: lf_procedure
            tpi::leaf_type::lf_procedure_16t: lf_procedure_16t
            tpi::leaf_type::lf_member: lf_member(false)
            tpi::leaf_type::lf_member_st: lf_member(true)
            tpi::leaf_type::lf_modifier: lf_modifier
            tpi::leaf_type::lf_modifier_16t: lf_modifier_16t
            tpi::leaf_type::lf_one_method: lf_one_method
            tpi::leaf_type::lf_mfunction: lf_mfunction
            tpi::leaf_type::lf_mfunction_16t: lf_mfunction_16t
            tpi::leaf_type::lf_arglist: lf_arglist
            tpi::leaf_type::lf_arglist_16t: lf_arglist_16t
            tpi::leaf_type::lf_bitfield: lf_bitfield
            tpi::leaf_type::lf_union: lf_union(false)
            tpi::leaf_type::lf_union_st: lf_union(true)
            tpi::leaf_type::lf_vtshape: lf_vtshape
            tpi::leaf_type::lf_methodlist: lf_methodlist
            tpi::leaf_type::lf_methodlist_16t: lf_methodlist_16t
            _: lf_unknown
      - id: invoke_end_body
        if: end_body_pos >= 0
        size: 0
      # skip any remaining data (when in top-level)
      - size-eos: true
        if: nested == false
      # skip trailing padding (when nested)
      - size: padding_size
        if: nested == true
    instances:
      trailing_byte:
        if: end_body_pos < _io.size
        pos: end_body_pos
        type: u1
      has_padding:
        value: trailing_byte >= tpi::leaf_type::lf_pad1.to_i
          and trailing_byte <= tpi::leaf_type::lf_pad15.to_i
      padding_size:
        value: 'has_padding ? trailing_byte & 0xF : 0'
      end_body_pos:
        value: _io.pos
  tpi_type:
    params:
      - id: ti
        type: u4
    seq:
      - id: hash
        if: _root.pdb_type == pdb_type::old
        type: u2
      - id: length
        type: u2
      - id: invoke_data_pos
        if: data_pos >= 0
        size: 0
      # skip data
      - size: length
    instances:
      data_pos:
        value: _io.pos
      # data lazy parsing
      data:
        pos: data_pos
        size: length
        type: tpi_type_data(false)
        if: length > 0
  tpi_types:
    instances:
      types:
        pos: 0
        type: tpi_type(_root.min_type_index + _index)
        repeat: eos
  tpi:
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
      cv_access:
        1: private
        2: protected
        3: public
      cv_ptrtype:
        0: near
        1: far
        2: huge
        3: base_seg
        4: base_val
        5: base_seg_val
        6: base_addr
        7: base_seg_addr
        8: base_type
        9: base_self
        10: near32
        11: far32
        12: ptr64
        13: unused
      cv_ptrmode:
        0: pointer
        1: reference
        2: pointer_member_data
        3: pointer_member_function
        4: rvalue_reference
        5: reserved
      cv_pmtype:
        0: undef
        1: d_single
        2: d_multiple
        3: d_virtual
        4: d_general
        5: f_single
        6: f_multiple
        7: f_virtual
        8: f_general
      cv_methodprop: 
        0: vanilla
        1: virtual
        2: static
        3: friend
        4: intro
        5: pure_virtual
        6: pure_intro
      cv_hfa:
        0: none
        1: float
        2: double
        3: other
      cv_mocom_udt:
        0: none
        1: ref
        2: value
        3: interface
      cv_vts_desc:
        0: near
        1: far
        2: thin
        3: outer
        4: meta
        5: near32
        6: far32
        7: unused
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
        0x040c: lf_one_method_16t
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
        0x140b: lf_one_method_st
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
        0x1511: lf_one_method
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
      - id: types_data
        size-eos: true
    instances:
      types:
        size: 0
        type: tpi_types
        process: cat(types_data)
  dbi_header_flags:
    seq:
      - id: linked_incrementally
        type: b1
        doc: 'true if linked incrmentally (really just if ilink thunks are present)'
      - id: stripped
        type: b1
        doc: 'true if PDB::CopyTo stripped the private data out'
      - id: ctypes
        type: b1
        doc: 'true if this PDB is using CTypes.'
      - type: b13
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
        doc: 'build version of the pdb dll that built this pdb last.'
      - id: symbol_records_stream
        type: pdb_stream_ref
      - id: rbld_version
        type: u2
        doc: 'rbld version of the pdb dll that built this pdb last.'
      - id: module_list_size
        type: u4
        doc: 'size of rgmodi substream'
      - id: section_contribution_size
        type: u4
        doc: 'size of Section Contribution substream'
      - id: section_map_size
        type: u4
      - id: file_info_size
        type: u4
      - id: type_server_map_size
        type: u4
        doc: 'size of the Type Server Map substream'
      - id: mfc_type_server_index
        type: u4
        doc: 'index of MFC type server'
      - id: debug_header_size
        type: u4
        doc: 'size of optional DbgHdr info appended to the end of the stream'
      - id: ec_substream_size
        type: u4
        doc: 'number of bytes in EC substream, or 0 if EC no EC enabled Mods'
      - id: flags
        type: dbi_header_flags
      - id: machine_type
        type: u2
      - id: reserved
        type: u4
    instances:
      ps_symbols_data:
        size: 0
        if: ps_symbols_stream.stream_number > -1
        process: cat(ps_symbols_stream.data)
        type: public_symbols_stream
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
        doc: 'NI for src file name'
      - id: pdb_filename_index
        type: u4
        doc: 'NI for path to compiler PDB'
  align:
    params:
      - id: value
        type: u4
      - id: alignment
        type: u4
    instances:
      aligned:
        value: (value + alignment - 1) & ((alignment - 1) ^ -1)
  module_info_flags:
    seq:
      - id: written
        type: b1
        doc: 'TRUE if mod has been written since DBI opened'
      - id: ec_enabled
        type: b1
        doc: 'TRUE if mod has EC symbolic information'
      - type: b6
      - id: tsm_list_index
        type: b8
        doc: 'index into TSM list for this mods server'
  sym_objname:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: signature
        type: u4
        doc: 'signature'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_compile:
    seq:
      - id: machine
        type: u1
        doc: 'target processor'
      - id: language
        type: u1
        doc: 'language index'
      - id: pcode
        type: b1
        doc: 'true if pcode present'
      - id: floatprec
        type: b2
        doc: 'floating precision'
      - id: floatpkg
        type: b2
        doc: 'float package'
      - id: ambdata
        type: b3
        doc: 'ambient data model'
      - id: ambcode
        type: b3
        doc: 'ambient code model'
      - id: mode32
        type: b1
        doc: 'true if compiled 32 bit mode'
      - id: pad
        type: b4
        doc: 'reserved'
      - id: ver
        type: pdb_string(true)
        doc: 'Length-prefixed compiler version string'
  sym_constant:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index (containing enum if enumerate) or metadata token'
      - id: value
        type: u2
        doc: 'numeric leaf containing value'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_udt:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_label32:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: offset
        type: u4
      - id: segment
        type: u2
      - id: flags
        type: cv_proc_flags
        doc: 'flags'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_register32:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
      - id: register
        type: u2
        doc: 'register enumerate'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_bprel32:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: offset
        type: u4
        doc: 'BP-relative offset'
      - id: type
        type: tpi_type_ref
        doc: 'Type index or Metadata token'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_data32:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
      - id: offset
        type: u4
      - id: segment
        type: u2
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_proc32:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
      - id: next
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to next symbol'
      - id: length
        type: u4
        doc: 'Proc length'
      - id: dbg_start
        type: u4
        doc: 'Debug start offset'
      - id: dbg_end
        type: u4
        doc: 'Debug end offset'
      # FIXME: ID handling
      - id: type
        type: tpi_type_ref
        doc: 'Type index or ID'
      - id: offset
        type: u4
      - id: segment
        type: u2
      - id: flags
        type: cv_proc_flags
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
  sym_thunk32:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
      - id: next
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to next symbol'
      - id: offset
        type: u4
      - id: segment
        type: u2
      - id: length
        type: u2
        doc: 'length of thunk'
      - id: ordinal
        type: u1
        doc: 'ordinal specifying type of thunk'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
      # FIXME
      - id: variant
        size-eos: true
  dbi_symbol_ref:
    params:
      - id: module_index
        type: u4
    seq:
      - id: offset
        type: u4
    instances:
      zzz_module_io:
        type: get_module_io(module_index)
      module_io:
        value: zzz_module_io.value
      symbol:
        io: module_io
        pos: offset
        type: dbi_symbol(module_index)
  get_module_io:
    params:
      - id: module_index
        type: u4
    instances:
      value:
        value: _root.dbi.modules.modules[module_index].module_data.symbols._io
  dbi_symbol_data:
    params:
      - id: length
        type: u2
    seq:
      - id: type
        type: u2
        enum: dbi::symbol_type
      - id: body
        if: length > 2
        type:
          switch-on: type
          cases:
            dbi::symbol_type::s_objname: sym_objname(false)
            dbi::symbol_type::s_objname_st: sym_objname(true)
            dbi::symbol_type::s_compile: sym_compile
            dbi::symbol_type::s_constant: sym_constant(false)
            dbi::symbol_type::s_constant_st: sym_constant(true)
            dbi::symbol_type::s_udt: sym_udt(false)
            dbi::symbol_type::s_udt_st: sym_udt(true)
            dbi::symbol_type::s_gproc32: sym_proc32(false)
            dbi::symbol_type::s_gproc32_st: sym_proc32(true)
            dbi::symbol_type::s_lproc32: sym_proc32(false)
            dbi::symbol_type::s_lproc32_st: sym_proc32(true)
            dbi::symbol_type::s_lproc32_dpc: sym_proc32(false)
            dbi::symbol_type::s_bprel32: sym_bprel32(false)
            dbi::symbol_type::s_bprel32_st: sym_bprel32(true)
            dbi::symbol_type::s_register: sym_register32(false)
            dbi::symbol_type::s_register_st: sym_register32(true)
            dbi::symbol_type::s_label32: sym_label32(false)
            dbi::symbol_type::s_label32_st: sym_label32(true)
            dbi::symbol_type::s_ldata32: sym_data32(false)
            dbi::symbol_type::s_ldata32_st: sym_data32(true)
            dbi::symbol_type::s_gdata32: sym_data32(false)
            dbi::symbol_type::s_gdata32_st: sym_data32(true)
            dbi::symbol_type::s_pub32: sym_data32(false)
            dbi::symbol_type::s_pub32_st: sym_data32(true)
            dbi::symbol_type::s_thunk32: sym_thunk32(false)
            dbi::symbol_type::s_thunk32_st: sym_thunk32(true)
            _: sym_unknown
    instances:
      module_index:
        value: _parent.module_index
  dbi_symbol:
    params:
      - id: module_index
        type: u4
    seq:
      - id: length
        type: u2
      - id: invoke_data_pos
        if: data_pos >= 0
        size: 0
      # skip data
      - size: length
    instances:
      data_pos:
        value: _io.pos
      data:
        pos: data_pos
        size: length
        type: dbi_symbol_data(length)
        if: length > 0
  module_symbols:
    params:
      - id: module_index
        type: u4
    instances:
      symbols:
        pos: 0
        type: dbi_symbol(module_index)
        repeat: eos
  module_stream:
    params:
      - id: module_index
        type: u4
    enums:
      cv_signature:
        0: c6
        1: c7
        2: c11
        4: c13
    seq:
      - id: signature
        type: u4
        enum: cv_signature
      - id: symbols
        if: symbols_size > 0
        size: symbols_size
        type: module_symbols(module_index)
    instances:
      symbols_size:
        value: _parent.symbols_size - 4
  module_info:
    params:
      - id: module_index
        type: u4
    seq:
      - id: invoke_position_start
        size: 0
        if: position_start >= 0
      - id: open_module_handle
        type: u4
      - id: section_contribution
        type: 
          switch-on: _root.pdb_type
          cases:
            pdb_type::big: section_contrib
            pdb_type::small: section_contrib40
      - id: flags
        type: module_info_flags
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
      module_data:
          size: 0
          if: stream.stream_number > -1
          process: cat(stream.data)
          type: module_stream(module_index)
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
        type: module_info(_index)
        repeat: eos
      - size-eos: true
  section_contribution_list:
    enums:
      version_type:
        # 0xeffe0000 + 19970605
        0xF12EBA2D: v60
        # 0xeffe0000 + 20140516
        0xF13151E4: new
    seq:
      - size: 4
        if: 'version == version_type::v60 or version == version_type::new'
      - id: items
        repeat: eos
        type:
          switch-on: version
          cases:
            version_type::v60: section_contrib
            version_type::new: section_contrib2
            _: section_contrib40
    instances:
      version:
        pos: 0
        type: u4
        enum: version_type
      item_size:
        value: 'version == version_type::new
          ? sizeof<section_contrib2> : version == version_type::v60
          ? sizeof<section_contrib> : sizeof<section_contrib40>'
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
        doc: 'descriptor flags bit field.'
      - id: overlay_number
        type: u2
        doc: 'the logical overlay number'
      - id: group_index
        type: u2
        doc: 'group index into the descriptor array'
      - id: segment_index
        type: u2
        doc: 'logical segment index - interpreted via flags'
      - id: segment_name_index
        type: u2
        doc: 'segment or group name - index into sstSegName'
      - id: class_name_index
        type: u2
        doc: 'class name - index into sstSegName'
      - id: offset
        type: u4
        doc: 'byte offset of the logical within the physical segment'
      - id: size
        type: u4
        doc: 'byte count of the logical segment or group'
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
  pdb_array:
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
  pdb_buffer:
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
        type: pdb_buffer
      - id: indices
        type: pdb_array(4)
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
  fpo_data:
    enums:
      frame_type:
        0: fpo
        1: trap
        2: tss
        3: std
    seq:
      - id: start_offset
        type: u4
        doc: 'offset 1st byte of function code'
      - id: proc_size
        type: u4
        doc: '# bytes in function'
      - id: num_dwords_locals
        type: u4
        doc: '# bytes in locals/4'
      - id: num_dwords_params
        type: u2
        doc: '# bytes in params/4'
      - id: prolog_size
        type: u1
        doc: '# bytes in prolog'
      - id: regs_size
        type: b3
        doc: '# regs saved'
      - id: has_seh
        type: b1
        doc: 'TRUE if SEH in func'
      - id: use_bp
        type: b1
        doc: 'TRUE if EBP has been allocated'
      - id: reserved
        type: b1
        doc: 'reserved for future use'
      - id: frame_type
        type: b2
        doc: 'frame type'
        enum: frame_type
  fpo_stream:
    seq:
      - id: items
        repeat: eos
        type: fpo_data
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
      fpo_stream_data:
        if: fpo_stream.stream_number > -1
        size: 0
        process: cat(fpo_stream.data)
        type: fpo_stream
      section_hdr_stream_data:
        if: section_hdr_stream.stream_number > -1
        size: 0
        process: cat(section_hdr_stream.data)
        type: debug_section_hdr_stream
  dbi:
    enums:
      symbol_type:
        0x0001: s_compile
        0x0002: s_register_16t
        0x0003: s_constant_16t
        0x0004: s_udt_16t
        0x0005: s_ssearch
        0x0006: s_end
        0x0007: s_skip
        0x0008: s_cvreserve
        0x0009: s_objname_st
        0x000a: s_endarg
        0x000b: s_coboludt_16t
        0x000c: s_manyreg_16t
        0x000d: s_return
        0x000e: s_entrythis
        0x0100: s_bprel16
        0x0101: s_ldata16
        0x0102: s_gdata16
        0x0103: s_pub16
        0x0104: s_lproc16
        0x0105: s_gproc16
        0x0106: s_thunk16
        0x0107: s_block16
        0x0108: s_with16
        0x0109: s_label16
        0x010a: s_cexmodel16
        0x010b: s_vftable16
        0x010c: s_regrel16
        0x0200: s_bprel32_16t
        0x0201: s_ldata32_16t
        0x0202: s_gdata32_16t
        0x0203: s_pub32_16t
        0x0204: s_lproc32_16t
        0x0205: s_gproc32_16t
        0x0206: s_thunk32_st
        0x0207: s_block32_st
        0x0208: s_with32_st
        0x0209: s_label32_st
        0x020a: s_cexmodel32
        0x020b: s_vftable32_16t
        0x020c: s_regrel32_16t
        0x020d: s_lthread32_16t
        0x020e: s_gthread32_16t
        0x020f: s_slink32
        0x0300: s_lprocmips_16t
        0x0301: s_gprocmips_16t
        0x0400: s_procref_st
        0x0401: s_dataref_st
        0x0402: s_align
        0x0403: s_lprocref_st
        0x0404: s_oem
        0x1000: s_ti16_max
        0x1001: s_register_st
        0x1002: s_constant_st
        0x1003: s_udt_st
        0x1004: s_coboludt_st
        0x1005: s_manyreg_st
        0x1006: s_bprel32_st
        0x1007: s_ldata32_st
        0x1008: s_gdata32_st
        0x1009: s_pub32_st
        0x100a: s_lproc32_st
        0x100b: s_gproc32_st
        0x100c: s_vftable32
        0x100d: s_regrel32_st
        0x100e: s_lthread32_st
        0x100f: s_gthread32_st
        0x1010: s_lprocmips_st
        0x1011: s_gprocmips_st
        0x1012: s_frameproc
        0x1013: s_compile2_st
        0x1014: s_manyreg2_st
        0x1015: s_lprocia64_st
        0x1016: s_gprocia64_st
        0x1017: s_localslot_st
        0x1018: s_paramslot_st
        0x1019: s_annotation
        0x101a: s_gmanproc_st
        0x101b: s_lmanproc_st
        0x101c: s_reserved1
        0x101d: s_reserved2
        0x101e: s_reserved3
        0x101f: s_reserved4
        0x1020: s_lmandata_st
        0x1021: s_gmandata_st
        0x1022: s_manframerel_st
        0x1023: s_manregister_st
        0x1024: s_manslot_st
        0x1025: s_manmanyreg_st
        0x1026: s_manregrel_st
        0x1027: s_manmanyreg2_st
        0x1028: s_mantypref
        0x1029: s_unamespace_st
        0x1100: s_st_max
        0x1101: s_objname
        0x1102: s_thunk32
        0x1103: s_block32
        0x1104: s_with32
        0x1105: s_label32
        0x1106: s_register
        0x1107: s_constant
        0x1108: s_udt
        0x1109: s_coboludt
        0x110a: s_manyreg
        0x110b: s_bprel32
        0x110c: s_ldata32
        0x110d: s_gdata32
        0x110e: s_pub32
        0x110f: s_lproc32
        0x1110: s_gproc32
        0x1111: s_regrel32
        0x1112: s_lthread32
        0x1113: s_gthread32
        0x1114: s_lprocmips
        0x1115: s_gprocmips
        0x1116: s_compile2
        0x1117: s_manyreg2
        0x1118: s_lprocia64
        0x1119: s_gprocia64
        0x111a: s_localslot
        0x111b: s_paramslot
        0x111c: s_lmandata
        0x111d: s_gmandata
        0x111e: s_manframerel
        0x111f: s_manregister
        0x1120: s_manslot
        0x1121: s_manmanyreg
        0x1122: s_manregrel
        0x1123: s_manmanyreg2
        0x1124: s_unamespace
        0x1125: s_procref
        0x1126: s_dataref
        0x1127: s_lprocref
        0x1128: s_annotationref
        0x1129: s_tokenref
        0x112a: s_gmanproc
        0x112b: s_lmanproc
        0x112c: s_trampoline
        0x112d: s_manconstant
        0x112e: s_attr_framerel
        0x112f: s_attr_register
        0x1130: s_attr_regrel
        0x1131: s_attr_manyreg
        0x1132: s_sepcode
        0x1133: s_local_2005
        0x1134: s_defrange_2005
        0x1135: s_defrange2_2005
        0x1136: s_section
        0x1137: s_coffgroup
        0x1138: s_export
        0x1139: s_callsiteinfo
        0x113a: s_framecookie
        0x113b: s_discarded
        0x113c: s_compile3
        0x113d: s_envblock
        0x113e: s_local
        0x113f: s_defrange
        0x1140: s_subfield
        0x1141: s_defrange_register
        0x1142: s_defrange_framepointer_rel
        0x1143: s_defrange_subfield_register
        0x1144: s_defrange_framepointer_rel_full_scope
        0x1145: s_defrange_register_rel
        0x1146: s_lproc32_id
        0x1147: s_gproc32_id
        0x1148: s_lprocmips_id
        0x1149: s_gprocmips_id
        0x114a: s_lprocia64_id
        0x114b: s_gprocia64_id
        0x114c: s_buildinfo
        0x114d: s_inlinesite
        0x114e: s_inlinesite_end
        0x114f: s_proc_id_end
        0x1150: s_defrange_hlsl
        0x1151: s_gdata_hlsl
        0x1152: s_ldata_hlsl
        0x1153: s_filestatic
        0x1154: s_local_dpc_groupshared
        0x1155: s_lproc32_dpc
        0x1156: s_lproc32_dpc_id
        0x1157: s_defrange_dpc_ptr_tag
        0x1158: s_dpc_sym_tag_map
        0x1159: s_armswitchtable
        0x115a: s_callees
        0x115b: s_callers
        0x115c: s_pogodata
        0x115d: s_inlinesite2
        0x115e: s_heapallocsite
        0x115f: s_mod_typeref
        0x1160: s_ref_minipdb
        0x1161: s_pdbmap
        0x1162: s_gdata_hlsl32
        0x1163: s_ldata_hlsl32
        0x1164: s_gdata_hlsl32_ex
        0x1165: s_ldata_hlsl32_ex
        0x1167: s_fastlink
        0x1168: s_inlinees
    seq:
      - id: header_old
        if: is_new_hdr == false
        type: dbi_header_old
      - id: header_new
        if: is_new_hdr == true
        type: dbi_header_new
      - id: modules
        if: header_new.module_list_size > 0
        size: 'is_new_hdr ? header_new.module_list_size : header_old.module_list_size'
        type: module_list
      - id: section_contributions
        if: header_new.section_contribution_size > 0
        size: 'is_new_hdr ? header_new.section_contribution_size : header_old.section_contribution_size'
        type: section_contribution_list
      - id: section_map
        size: 'is_new_hdr ? header_new.section_map_size : header_old.section_map_size'
        if: header_new.section_map_size > 0
        type: omf_segment_map
      ## below portions are only present in DBI new
      - id: file_info
        if: is_new_hdr and header_new.file_info_size > 0
        size: header_new.file_info_size
        type: file_info
      - id: type_server_map
        size: header_new.type_server_map_size
        if: is_new_hdr and header_new.type_server_map_size > 0
        type: type_server_map
      - id: ec_info
        if: is_new_hdr and header_new.ec_substream_size > 0
        size: header_new.ec_substream_size
        type: name_table
      - id: debug_data
        if: is_new_hdr and header_new.debug_header_size > 0
        size: header_new.debug_header_size
        type: debug_data
    instances:
      is_new_hdr:
        value: signature == -1
      # invalid gs/ps syms marker for DBI old/new detection
      signature:
        pos: 0
        type: s4
  pdb_header_jg:
    seq:
      - size: 2
      - id: page_size
        type: u4
      - id: fpm_page_number
        type: u2
      - id: num_pages
        type: u2
      - id: directory_size
        type: u4
      - id: page_map
        type: u4
  pdb_header_jg_old:
    seq:
      - size: 2
      - id: pdb_internal_version
        type: u4
        enum: pdb_version
      - id: timestamp
        type: u4
      - id: age
        type: u4
      - id: min_ti
        type: u2
      - id: max_ti
        type: u2
      - id: gp_rec_size
        type: u4
  pdb_jg_old:
    seq:
      - id: header
        type: pdb_header_jg_old
      - id: types
        repeat: eos
        type: tpi_type(header.min_ti + _index)
  pdb_jg:
    seq:
      - id: header
        type: pdb_header_jg
      - id: stream_table_pages
        type: pdb_page_number_list(num_stream_table_pages)
        size: header.page_size * num_stream_table_pages
    instances:
      zzz_num_stream_table_pages:
        type: get_num_pages2(header.directory_size, header.page_size)
      num_stream_table_pages:
        value: zzz_num_stream_table_pages.num_pages
      stream_table:
        size: 0
        process: concat_pages(stream_table_pages.pages)
        type: pdb_stream_table
  pdb_ds:
    seq:
      - id: header
        type: pdb_header_ds
      - id: stream_table_root_pagelist_data
        type: pdb_pagelist(num_stream_table_pagelist_pages, header.page_size)
        size: header.page_size * num_stream_table_pagelist_pages
    instances:
      zzz_num_stream_table_pages:
        type: get_num_pages2(header.directory_size, header.page_size)
      # number of pages required for the stream table
      num_stream_table_pages:
        value: zzz_num_stream_table_pages.num_pages
      stream_table_page_list_size:
        value:
          num_stream_table_pages * sizeof<u4>
      zzz_num_stream_table_pagelist_pages:
        type: get_num_pages2(stream_table_page_list_size, header.page_size)
      # number of pages required for the list of pages (u4 * num_pages)
      num_stream_table_pagelist_pages:
        value: zzz_num_stream_table_pagelist_pages.num_pages

      # holds page numbers for the directory page list
      stream_table_root_pages:
        io: stream_table_root_pagelist_data._io
        pos: 0
        type: pdb_page_number
        repeat: expr
        repeat-expr: num_stream_table_pagelist_pages
      # holds page numbers for the stream table
      stream_table_pages:
        size: 0
        process: concat_pages(stream_table_root_pages)
        type: pdb_page_number_list(num_stream_table_pages)
      stream_table:
        size: 0
        process: concat_pages(stream_table_pages.pages)
        type: pdb_stream_table
seq:
  - id: signature
    type: pdb_signature
  - id: pdb_ds
    if: signature.id == "DS"
    type: pdb_ds
  - id: pdb_jg
    if: signature.id == "JG" and signature.version_major == "2"
    type: pdb_jg
  - id: pdb_jg_old
    if: signature.id == "JG" and signature.version_major == "1"
    type: pdb_jg_old
instances:
  page_number_size:
    value: 'pdb_type == pdb_type::big ? 4 : 2'
  page_size_ds:
    if: pdb_type == pdb_type::big
    value: pdb_ds.header.page_size
  page_size_jg:
    if: pdb_type == pdb_type::small
    value: pdb_jg.header.page_size
  page_size:
    value: 'pdb_type == pdb_type::big ? page_size_ds
      : pdb_type == pdb_type::small ? page_size_jg
      : 0'
  pdb_type:
    value: '_root.signature.id == "DS"
      ? pdb_type::big 
      : (_root.signature.id == "JG" and _root.signature.version_major == "2")
      ? pdb_type::small
      : pdb_type::old'
  num_streams:
    value: 'pdb_type == pdb_type::big
      ? pdb_ds.stream_table.num_streams
      : pdb_type == pdb_type::small 
      ? pdb_jg.stream_table.num_streams : 0'
  zzz_tpi_data:
    type: get_stream_data(default_stream::tpi.to_i)
  zzz_dbi_data:
    type: get_stream_data(default_stream::dbi.to_i)
  stream_table:
    if: pdb_type == pdb_type::big or pdb_type == pdb_type::small
    value: 'pdb_type == pdb_type::big 
          ? _root.pdb_ds.stream_table
          : _root.pdb_jg.stream_table'
  
  min_type_index:
    value: 'pdb_type == pdb_type::old
      ? pdb_jg_old.header.min_ti
      : tpi.header.min_type_index'
  max_type_index:
    value: 'pdb_type == pdb_type::old
      ? pdb_jg_old.header.max_ti
      : tpi.header.max_type_index'
  types:
    value: 'pdb_type == pdb_type::old
      ? pdb_jg_old.types
      : tpi.types.types'
  tpi:
    size: 0
    type: tpi
    process: cat(zzz_tpi_data.value)
  dbi:
    size: 0
    type: dbi
    process: cat(zzz_dbi_data.value)
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
  pdb_version:
    920924: v41
    #19960502: v50
    19960502: v60
    19970116: v50a
    19980914: v61
    19990511: v69
    20000406: v70_deprecated
    20001102: v70
    20030901: v80
    20091201: v110
  