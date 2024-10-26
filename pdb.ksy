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
  pdb_stream_ref_x:
    params:
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
  pdb_stream_ref:
    seq:
      - id: stream_number
        type: s2
    instances:
      stream:
        type: pdb_stream_ref_x(stream_number)
      size:
        value: stream.size
      data:
        if: stream.is_valid_stream
        value: stream.zzz_data.value
  pdb_stream_entry_jg:
    doc-ref: 'SI_PERSIST'
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
    doc-ref: 'SI_PERSIST'
    params:
      - id: stream_number
        type: s4
    seq:
      - id: stream_size
        type: s4
    instances:
      zzz_num_directory_pages:
        type: get_num_pages(stream_size)
      num_directory_pages:
        value: '(stream_size < 0) ? 0 : zzz_num_directory_pages.num_pages'
  pdb_stream_data:
    params:
      - id: stream_size
        type: s4
    seq:
      - id: data
        if: stream_size > 0
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
      has_data:
        value: stream_size > 0
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
      has_data:
        value: '_root.pdb_type == pdb_type::big
          ? _root.pdb_ds.stream_table.streams[stream_number].has_data
          : _root.pdb_jg.stream_table.streams[stream_number].has_data'
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
    doc-ref: 'PSGSIHDR'
    seq:
      - id: sym_hash_size
        type: u4
        doc-ref: 'cbSymHash'
      - id: address_map_size
        type: u4
        doc-ref: 'cbAddrMap'
      - id: num_thunks
        type: u4
        doc-ref: 'nThunks'
      - id: thunk_size
        type: u4
        doc-ref: 'cbSizeOfThunk'
      - id: thunk_table_section_index
        type: u4
        doc-ref: 'isectThunkTable'
      - id: thunk_table_offset
        type: u4
        doc-ref: 'offThunkTable'
      - id: num_sections
        type: u4
        doc-ref: 'nSects'
  gsi_hdr:
    doc-ref: 'GSIHashHdr'
    enums:
      version:
        # 0xeffe0000 + 19990810
        0xF12F091A: v70
    seq:
      - id: signature
        type: u4
        doc-ref: 'verSignature'
      - id: version
        type: u4
        enum: version
        doc-ref: 'verHdr'
      - id: size_hash_records
        type: u4
        doc-ref: 'cbHr'
      - id: size_hash_buckets
        type: u4
        doc-ref: 'cbBuckets'
    instances:
      num_hash_records:
        value: size_hash_records / sizeof<gsi_hash_record>
  gsi_hash_record:
    doc-ref: 'HRFile'
    seq:
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: reference_count
        type: u4
        doc-ref: 'cRef'
  global_symbols_stream:
    seq:
      - if: has_compressed_buckets
        type: gsi_hdr
      - id: compressed_hash_records
        if: has_compressed_buckets
        type: gsi_hash_record
        repeat: expr
        repeat-expr: header.num_hash_records
      - id: hash_buckets
        if: has_compressed_buckets
        size: header.size_hash_buckets
      #- id: hash_records
      #  if: has_compressed_buckets == false
      #  type: gsi_hash_record
      # FIXME: uncompressed hash_records have varying size based on "m_fMinimalDbgInfo"
    instances:
      has_compressed_buckets:
        value: header.signature == 0xFFFFFFFF and header.version == gsi_hdr::version::v70
      header:
        pos: 0
        type: gsi_hdr
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
      symbols_data:
        size: 0
        if: symbol_records_stream.stream_number > -1
        process: cat(symbol_records_stream.data)
        type: symbol_records_stream
      gs_symbols_data:
        size: 0
        if: gs_symbols_stream.stream_number > -1
        process: cat(gs_symbols_stream.data)
        type: global_symbols_stream
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
        value: 'has_next_block == true ? next_block.type_index : _root.tpi.max_type_index'
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
  tpi_hash_head_list:
    seq:
      - id: name_to_type_index
        type: pdb_map(sizeof<u4>, sizeof<u4>)
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
        type: tpi_hash_head_list
  tpi_hash:
    doc-ref: 'TpiHash'
    seq:
      - id: hash_stream
        type: pdb_stream_ref
        doc: 'main hash stream'
        doc-ref: 'SN'
      - id: aux_hash_stream
        type: pdb_stream_ref
        doc: 'auxilliary hash data if necessary'
        doc-ref: 'snPad'
      - id: hash_key_size
        type: u4
        doc: 'size of hash key'
        doc-ref: 'cbHashKey'
      - id: num_hash_buckets
        type: u4
        doc: 'how many buckets we have'
        doc-ref: 'cHashBuckets'
      - id: hash_values_slice
        type: tpi_slice
        doc: 'offcb of hashvals'
        doc-ref: 'offcbHashVals'
      - id: type_offsets_slice
        type: tpi_slice
        doc: 'offcb of (TI,OFF) pairs'
        doc-ref: 'offcbTiOff'
      - id: hash_head_list_slice
        type: tpi_slice
        doc: 'offcb of hash head list, maps (hashval,ti), where ti is the head of the hashval chain.'
        doc-ref: 'offcbHashAdj'
    instances:
      tpi_hash_data:
        size: 0
        process: cat(hash_stream.data)
        type: tpi_hash_data

  
  tpi_header16:
    doc-ref: 'HDR_16t'
    seq:
      - id: version
        type: u4
        enum: tpi::tpi_version
        doc: 'version which created this TypeServer'
        doc-ref: 'vers'
      - id: min_type_index
        type: u2
        doc: 'lowest TI'
        doc-ref: 'tiMin'
      - id: max_type_index
        type: u2
        doc: 'highest TI + 1'
        doc-ref: 'tiMac'
      - id: gp_rec_size
        type: u4
        doc: 'count of bytes used by the gprec which follows.'
        doc-ref: 'cbGprec'
      - id: hash_stream
        type: pdb_stream_ref
        doc: 'stream to hold hash values'
        doc-ref: 'snHash'
  
  tpi_header:
    doc-ref: 'HDR'
    seq:
      - id: version
        type: u4
        enum: tpi::tpi_version
        doc: 'version which created this TypeServer'
        doc-ref: 'vers'
      - id: header_size
        type: u4
        doc: 'size of the header, allows easier upgrading and backwards compatibility'
        doc-ref: 'cbHdr'
      - id: min_type_index
        type: u4
        doc: 'lowest TI'
        doc-ref: 'tiMin'
      - id: max_type_index
        type: u4
        doc: 'highest TI + 1'
        doc-ref: 'tiMac'
      - id: gp_rec_size
        type: u4
        doc: 'count of bytes used by the gprec which follows.'
        doc-ref: 'cbGprec'
      - id: hash
        type: tpi_hash
        doc: 'hash stream schema'
        doc-ref: 'tpihash'
  cv_numeric_literal:
    params:
      - id: value
        type: u2
  lf_char:
    seq:
      - id: value
        type: s1
  cv_properties:
    doc-ref: 'CV_prop_t'
    seq:
      - id: packed
        type: b1
        doc: 'true if structure is packed'
        doc-ref: 'packed'
      - id: ctor
        type: b1
        doc: 'true if constructors or destructors present'
        doc-ref: 'ctor'
      - id: overlapped_operators
        type: b1
        doc: 'true if overloaded operators present'
        doc-ref: 'ovlops'
      - id: is_nested
        type: b1
        doc: 'true if this is a nested class'
        doc-ref: 'isnested'
      - id: contains_nested
        type: b1
        doc: 'true if this class contains nested types'
        doc-ref: 'cnested'
      - id: overlapped_assignment
        type: b1
        doc: 'true if overloaded assignment (=)'
        doc-ref: 'opassign'
      - id: casting_methods
        type: b1
        doc: 'true if casting methods'
        doc-ref: 'opcast'
      - id: forward_reference
        type: b1
        doc: 'true if forward reference (incomplete defn)'
        doc-ref: 'fwdref'
      - id: scoped_definition
        type: b1
        doc: 'scoped definition'
        doc-ref: 'scoped'
      - id: has_unique_name
        type: b1
        doc: 'true if there is a decorated name following the regular name'
        doc-ref: 'hasuniquename'
      - id: sealed
        type: b1
        doc: 'true if class cannot be used as a base class'
        doc-ref: 'sealed'
      - id: hfa
        type: b2
        enum: tpi::cv_hfa
        doc: 'CV_HFA_e'
        doc-ref: 'hfa'
      - id: intrinsic
        type: b1
        doc: 'true if class is an intrinsic type (e.g. __m128d)'
        doc-ref: 'intrinsic'
      - id: mocom
        type: b2
        enum: tpi::cv_mocom_udt
        doc: 'CV_MOCOM_UDT_e'
        doc-ref: 'mocom'
  cv_proc_flags:
    doc-ref: 'CV_PROCFLAGS'
    seq:
      - id: nofpo
        type: b1
        doc: 'frame pointer present'
        doc-ref: 'CV_PFLAG_NOFPO'
      - id: interrupt
        type: b1
        doc: 'interrupt return'
        doc-ref: 'CV_PFLAG_INT'
      - id: far_return
        type: b1
        doc: 'far return'
        doc-ref: 'CV_PFLAG_FAR'
      - id: never
        type: b1
        doc: 'function does not return'
        doc-ref: 'CV_PFLAG_NEVER'
      - id: not_reached
        type: b1
        doc: 'label isn''t fallen into'
        doc-ref: 'CV_PFLAG_NOTREACHED'
      - id: cust_call
        type: b1
        doc: 'custom calling convention'
        doc-ref: 'CV_PFLAG_CUST_CALL'
      - id: no_inline
        type: b1
        doc: 'function marked as noinline'
        doc-ref: 'CV_PFLAG_NOINLINE'
      - id: opt_debug_info
        type: b1
        doc: 'function has debug information for optimized code'
        doc-ref: 'CV_PFLAG_OPTDBGINFO'
  cv_func_attributes:
    doc-ref: 'CV_funcattr_t'
    seq:
      - id: cxx_return_udt
        type: b1
        doc: 'true if C++ style ReturnUDT'
        doc-ref: 'cxxreturnudt'
      - id: is_constructor
        type: b1
        doc: 'true if func is an instance constructor'
        doc-ref: 'ctor'
      - id: is_virtual_constructor
        type: b1
        doc-ref: 'ctorvbase'
        doc: 'true if func is an instance constructor of a class with virtual bases'
      - type: b5
        doc: 'unused'
        doc-ref: 'unused'
  cv_field_attributes:
    doc-ref: 'CV_fldattr_t'
    seq:
      - id: access_protection
        type: b2
        doc: 'access protection'
        doc-ref: 'access'
        enum: tpi::cv_access
      - id: method_properties
        type: b3
        enum: tpi::cv_methodprop
        doc: 'method properties'
        doc-ref: 'mprop'
      - id: is_pseudo
        type: b1
        doc: 'compiler generated fcn and does not exist'
        doc-ref: 'pseudo'
      - id: no_inherit
        type: b1
        doc: 'true if class cannot be inherited'
        doc-ref: 'noinherit'
      - id: no_construct
        type: b1
        doc: 'true if class cannot be constructed'
        doc-ref: 'noconstruct'
      - id: compiler_generated
        type: b1
        doc: 'compiler generated fcn and does exist'
        doc-ref: 'compgenx'
      - id: is_sealed
        type: b1
        doc: 'true if method cannot be overridden'
        doc-ref: 'sealed'
      - type: b6
        doc: 'unused'
        doc-ref: 'unused'
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
    doc: 'LF_ENUM'
    doc-ref: 'lfEnum'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: num_elements
        type: u2
        doc: 'count of number of elements in class'
        doc-ref: 'count'
      - id: type_properties
        type: cv_properties
        doc: 'property attribute field'
        doc-ref: 'property'
      - id: underlying_type
        type: tpi_type_ref
        doc: 'underlying type of the enum'
        doc-ref: 'utype'
      - id: field_type
        type: tpi_type_ref
        doc: 'type index of LF_FIELD descriptor list'
        doc-ref: 'field'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'length prefixed name of enum'
        doc-ref: 'Name'
  lf_enumerate:
    doc: 'LF_ENUMERATE'
    doc-ref: 'lfEnumerate'
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'access'
        doc-ref: 'attr'
      - id: value
        type: cv_numeric_type
        doc: 'variable length value field'
        doc-ref: 'value'
      - id: field_name
        type: str
        encoding: UTF-8
        terminator: 0
        doc: 'length prefixed name'
  lf_fieldlist_16t:
    doc: 'LF_FIELDLIST_16t'
    doc-ref: 'lfFieldList_16t'
    seq:
      - id: data
        type: tpi_type_data(true)
        repeat: eos
        doc: 'field list sub lists'
        doc-ref: 'data'
  lf_fieldlist:
    doc: 'LF_FIELDLIST'
    doc-ref: 'lfFieldList'
    seq:
      - id: data
        type: tpi_type_data(true)
        repeat: eos
        doc: 'field list sub lists'
        doc-ref: 'data'
  lf_arglist:
    doc: 'LF_ARGLIST, LF_SUBSTR_LIST'
    doc-ref: 'lfArgList'
    seq:
      - id: count
        type: u4
        doc: 'number of arguments'
        doc-ref: 'count'
      - id: arguments
        type: tpi_type_ref
        repeat: expr
        repeat-expr: count
        doc: 'argument types'
        doc-ref: 'arg'
  lf_arglist_16t:
    doc: 'LF_ARGLIST_16t'
    doc-ref: 'lfArgList_16t'
    seq:
      - id: count
        type: u2
        doc: 'number of arguments'
        doc-ref: 'count'
      - id: arguments
        type: tpi_type_ref16
        repeat: expr
        repeat-expr: count
        doc: 'argument types'
        doc-ref: 'arg'
  lf_bitfield:
    doc: 'LF_BITFIELD'
    doc-ref: 'lfBitfield'
    seq: 
      - id: type
        type: tpi_type_ref
        doc: 'type of bitfield'
        doc-ref: 'type'
      - id: length
        type: u1
        doc-ref: 'length'
      - id: position
        type: u1
        doc-ref: 'position'
  lf_array_16t:
    doc: 'LF_ARRAY_16t'
    doc-ref: 'lfArray_16t'
    seq:
      - id: element_type
        type: tpi_type_ref16
        doc: 'type index of element type'
        doc-ref: 'elemtype'
      - id: indexing_type
        type: tpi_type_ref16
        doc: 'type index of indexing type'
        doc-ref: 'idxtype'
      - id: size
        type: cv_numeric_type
        doc: 'variable length data specifying size in bytes'
        doc-ref: 'data.size'
      - id: name
        type: pdb_string(true)
        doc: 'array name'
        doc-ref: 'data.name'
  lf_array:
    doc: 'LF_ARRAY'
    doc-ref: 'lfArray'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: element_type
        type: tpi_type_ref
        doc: 'type index of element type'
        doc-ref: 'elemtype'
      - id: indexing_type
        type: tpi_type_ref
        doc: 'type index of indexing type'
        doc-ref: 'idxtype'
      - id: size
        type: cv_numeric_type
        doc: 'variable length data specifying size in bytes'
        doc-ref: 'data.size'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'array name'
        doc-ref: 'data.name'
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
    doc: 'LF_CLASS_16t, LF_STRUCT_16t'
    doc-ref: 'lfClass_16t'
    seq:
      - id: number_of_elements
        type: u2
        doc: 'count of number of elements in class'
        doc-ref: 'count'
      - id: field_type
        type: tpi_type_ref16
        doc: 'type index of LF_FIELD descriptor list'
        doc-ref: 'field'
      - id: properties
        type: cv_properties
        doc: 'property attribute field (prop_t)'
        doc-ref: 'property'
      - id: derived_type
        type: tpi_type_ref16
        doc: 'type index of derived from list if not zero'
        doc-ref: 'derived'
      - id: vshape_type
        type: tpi_type_ref16
        doc: 'type index of vshape table for this class' 
        doc-ref: 'vshape'
      - id: struct_size
        type: cv_numeric_type
        doc: 'data describing length of structure in bytes'
        doc-ref: 'data.size'
      - id: name
        type: pdb_string(true)
        doc: 'class name'
        doc-ref: 'data.name'
  lf_class:
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: number_of_elements
        type: u2
        doc: 'count of number of elements in class'
        doc-ref: 'count'
      - id: properties
        type: cv_properties
        doc: 'property attribute field (prop_t)'
        doc-ref: 'property'
      - id: field_type
        type: tpi_type_ref
        doc: 'type index of LF_FIELD descriptor list'
        doc-ref: 'field'
      - id: derived_type
        type: tpi_type_ref
        doc: 'type index of derived from list if not zero'
        doc-ref: 'derived'
      - id: vshape_type
        type: tpi_type_ref
        doc: 'type index of vshape table for this class'
        doc-ref: 'vshape'
      - id: struct_size
        type: cv_numeric_type
        doc: 'data describing length of structure in bytes'
        doc-ref: 'data.size'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'class name'
        doc-ref: 'data.name'
  lf_pointer_attributes_16t:
    doc-ref: 'lfPointerAttr_16t'
    seq:
      - id: pointer_type
        type: b5
        enum: tpi::cv_ptrtype
        doc: 'ordinal specifying pointer type (CV_ptrtype_e)'
        doc-ref: 'ptrtype'
      - id: pointer_mode
        type: b3
        enum: tpi::cv_ptrmode
        doc: 'ordinal specifying pointer mode (CV_ptrmode_e)'
        doc-ref: 'ptrmode'
      - id: is_flat_32
        type: b1
        doc: 'true if 0:32 pointer'
        doc-ref: 'isflat32'
      - id: is_volatile
        type: b1
        doc: 'TRUE if volatile pointer'
        doc-ref: 'isvolatile'
      - id: is_const
        type: b1
        doc: 'TRUE if const pointer'
        doc-ref: 'isconst'
      - id: is_unaligned
        type: b1
        doc: 'TRUE if unaligned pointer'
        doc-ref: 'isunaligned'
      - type: b4
        doc: 'unused'
        doc-ref: 'unused'
  lf_pointer_attributes:
    doc-ref: 'lfPointerAttr'
    seq:
      - id: pointer_type
        type: b5
        enum: tpi::cv_ptrtype
        doc: 'ordinal specifying pointer type (CV_ptrtype_e)'
        doc-ref: 'ptrtype'
      - id: pointer_mode
        type: b3
        enum: tpi::cv_ptrmode
        doc: 'ordinal specifying pointer mode (CV_ptrmode_e)'
        doc-ref: 'ptrmode'
      - id: is_flat_32
        type: b1
        doc: 'true if 0:32 pointer'
        doc-ref: 'isflat32'
      - id: is_volatile
        type: b1
        doc: 'TRUE if volatile pointer'
        doc-ref: 'isvolatile'
      - id: is_const
        type: b1
        doc: 'TRUE if const pointer'
        doc-ref: 'isconst'
      - id: is_unaligned
        type: b1
        doc: 'TRUE if unaligned pointer'
        doc-ref: 'isunaligned'
      - id: is_restricted
        type: b1
        doc: 'TRUE if restricted pointer (allow agressive opts)'
        doc-ref: 'isrestrict'
      - id: size
        type: b6
        doc: 'size of pointer (in bytes)'
        doc-ref: 'size'
      - id: is_mocom
        type: b1
        doc: 'TRUE if it is a MoCOM pointer (^ or %)'
        doc-ref: 'ismocom'
      - id: is_lref
        type: b1
        doc: 'TRUE if it is this pointer of member function with & ref-qualifier'
        doc-ref: 'islref'
      - id: is_rref
        type: b1
        doc: 'TRUE if it is this pointer of member function with && ref-qualifier'
        doc-ref: 'isrref'
      - type: b10
        doc: 'unused'
        doc-ref: 'unused'
  lf_pointer:
    doc: 'LF_POINTER'
    doc-ref: 'lfPointer'
    seq:
      - id: underlying_type
        type: tpi_type_ref
        doc: 'type index of the underlying type'
        doc-ref: 'utype'
      - id: attributes
        type: lf_pointer_attributes
        doc-ref: 'attr'
  lf_pointer_16t:
    doc: 'LF_POINTER_16t'
    doc-ref: 'lfPointer_16t'
    seq:
      - id: attributes
        type: lf_pointer_attributes_16t
        doc-ref: 'attr'
      - id: underlying_type
        type: tpi_type_ref16
        doc: 'type index of the underlying type'
        doc-ref: 'utype'
  lf_member:
    doc: 'LF_MEMBER'
    doc-ref: 'lfMember'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'attribute mask'
        doc-ref: 'attr'
      - id: field_type
        type: tpi_type_ref
        doc: 'index of type record for field'
        doc-ref: 'index'
      - id: offset
        type: cv_numeric_type
        doc: 'variable length offset of field'
        doc-ref: 'offset'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'length prefixed name of field'
  lf_modifier_flags:
    doc-ref: 'CV_modifier_t'
    seq:
      - id: const
        type: b1
        doc: 'TRUE if constant'
        doc-ref: 'MOD_const'
      - id: volatile
        type: b1
        doc: 'TRUE if volatile'
        doc-ref: 'MOD_volatile'
      - id: unaligned
        type: b1
        doc: 'TRUE if unaligned'
        doc-ref: 'MOD_unaligned'
      - type: b13
        doc-ref: 'MOD_unused'
  lf_modifier_16t:
    doc: 'LF_MODIFIER_16t'
    doc-ref: 'lfModifier_16t'
    seq:
      - id: flags
        type: lf_modifier_flags
        doc: 'modifier attribute modifier_t'
        doc-ref: 'attr'
      - id: modified_type
        type: tpi_type_ref16
        doc: 'modified type'
        doc-ref: 'type'
  lf_modifier:
    doc: 'LF_MODIFIER'
    doc-ref: 'lfModifier'
    seq:
      - id: modified_type
        type: tpi_type_ref
        doc: 'modified type'
        doc-ref: 'type'
      - id: flags
        type: lf_modifier_flags
        doc: 'modifier attribute modifier_t'
        doc-ref: 'attr'
  lf_mfunction_16t:
    doc: 'LF_MFUNCTION_16t'
    doc-ref: 'lfMFunc_16t'
    seq:
      - id: return_type
        type: tpi_type_ref16
        doc: 'type index of return value'
        doc-ref: 'rvtype'
      - id: class_type
        type: tpi_type_ref16
        doc: 'type index of containing class'
        doc-ref: 'classtype'
      - id: this_type
        type: tpi_type_ref16
        doc: 'type index of this pointer (model specific)'
        doc-ref: 'thistype'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (call_t)'
        doc-ref: 'calltype'
      - id: attributes
        type: cv_func_attributes
        doc: 'attributes'
        doc-ref: 'funcattr'
      - id: parameters_count
        type: u2
        doc: 'number of parameters'
        doc-ref: 'parmcount'
      - id: argument_list_type
        type: tpi_type_ref16
        doc: 'type index of argument list'
        doc-ref: 'arglist'
      - id: this_adjuster
        type: u4
        doc: 'this adjuster (long because pad required anyway)'
        doc-ref: 'thisadjust'
  lf_mfunction:
    doc: 'LF_MFUNCTION'
    doc-ref: 'lfMFunc'
    seq:
      - id: return_type
        type: tpi_type_ref
        doc: 'type index of return value'
        doc-ref: 'rvtype'
      - id: class_type
        type: tpi_type_ref
        doc: 'type index of containing class'
        doc-ref: 'classtype'
      - id: this_type
        type: tpi_type_ref
        doc: 'type index of this pointer (model specific)'
        doc-ref: 'thistype'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (call_t)'
        doc-ref: 'calltype'
      - id: attributes
        type: cv_func_attributes
        doc: 'attributes'
        doc-ref: 'funcattr'
      - id: parameters_count
        type: u2
        doc: 'number of parameters'
        doc-ref: 'parmcount'
      - id: argument_list_type
        type: tpi_type_ref
        doc: 'type index of argument list'
        doc-ref: 'arglist'
      - id: this_adjuster
        type: u4
        doc: 'this adjuster (long because pad required anyway)'
        doc-ref: 'thisadjust'
  lf_one_method:
    doc: 'LF_ONEMETHOD'
    doc-ref: 'lfOneMethod'
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'method attribute'
        doc-ref: 'attr'
      - id: procedure_type
        type: tpi_type_ref
        doc: 'index to type record for procedure'
        doc-ref: 'index'
      - id: vtable_offset
        if: attributes.method_properties == tpi::cv_methodprop::intro
          or attributes.method_properties == tpi::cv_methodprop::pure_intro
        type: u4
        doc: 'offset in vfunctable if intro virtual'
        doc-ref: 'vbaseoff'
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
        doc: 'length prefixed name of method'
  ml_method_16t:
    doc-ref: 'mlMethod_16t'
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'method attribute'
        doc-ref: 'attr'
      - id: index_type
        type: tpi_type_ref16
        doc: 'index to type record for procedure'
        doc-ref: 'index'
      - id: vtable_offset
        if: attributes.method_properties == tpi::cv_methodprop::intro
          or attributes.method_properties == tpi::cv_methodprop::pure_intro
        type: u4
        doc: 'offset in vfunctable if intro virtual'
        doc-ref: 'vbaseoff'
  ml_method:
    doc-ref: 'mlMethod'
    seq:
      - id: attributes
        type: cv_field_attributes
        doc: 'method attribute'
        doc-ref: 'attr'
      - size: 2
        doc: 'internal padding, must be 0'
        doc-ref: 'pad0'
      - id: index_type
        type: tpi_type_ref
        doc: 'index to type record for procedure'
        doc-ref: 'index'
      - id: vtable_offset
        if: attributes.method_properties == tpi::cv_methodprop::intro
          or attributes.method_properties == tpi::cv_methodprop::pure_intro
        type: u4
        doc: 'offset in vfunctable if intro virtual'
        doc-ref: 'vbaseoff'
  lf_label:
    doc: 'LF_LABEL'
    doc-ref: 'lfLabel'
    seq:
      - id: mode
        type: u2
        doc: 'addressing mode of label'
  lf_methodlist_16t:
    doc-ref: 'lfMethodList_16t'
    seq:
      - id: methods
        type: ml_method_16t
        repeat: eos
  lf_methodlist:
    doc-ref: 'lfMethodList'
    seq:
      - id: methods
        type: ml_method
        repeat: eos
  lf_procedure_16t:
    doc-ref: 'lfProc_16t'
    seq:
      - id: return_value_type
        type: tpi_type_ref16
        doc: 'type index of return value'
        doc-ref: 'rvtype'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (CV_call_t)'
        doc-ref: 'calltype'
      - id: function_attributes
        type: cv_func_attributes
        doc: 'attributes'
        doc-ref: 'funcattr'
      - id: parameter_count
        type: u2
        doc: 'number of parameters'
        doc-ref: 'parmcount'
      - id: arglist
        type: tpi_type_ref16
        doc: 'type index of argument list'
        doc-ref: 'arglist'
  lf_procedure:
    doc-ref: 'lfProc'
    seq:
      - id: return_value_type
        type: tpi_type_ref
        doc: 'type index of return value'
        doc-ref: 'rvtype'
      - id: calling_convention
        type: u1
        enum: tpi::calling_convention
        doc: 'calling convention (CV_call_t)'
        doc-ref: 'calltype'
      - id: function_attributes
        type: cv_func_attributes
        doc: 'attributes'
        doc-ref: 'funcattr'
      - id: parameter_count
        type: u2
        doc: 'number of parameters'
        doc-ref: 'parmcount'
      - id: arglist
        type: tpi_type_ref
        doc: 'type index of argument list'
        doc-ref: 'arglist'
  lf_vftable_names:
    seq:
      - id: names
        type: str
        encoding: UTF-8
        terminator: 0
        repeat: eos
  lf_vftable:
    doc-ref: 'lfVftable'
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'class/structure that owns the vftable'
        doc-ref: 'type'
      - id: base_vftable
        type: tpi_type_ref
        doc: 'vftable from which this vftable is derived'
        doc-ref: 'baseVftable'
      - id: offset_in_object_layout
        type: u4
        doc: 'offset of the vfptr to this table, relative to the start of the object layout.'
        doc-ref: 'offsetInObjectLayout'
      - id: len
        type: u4
        doc: 'length of the Names array below in bytes.'
        doc-ref: 'len'
      - id: zzz_names_block
        size: len
        type: lf_vftable_names
        doc: 'array of names. The first is the name of the vtable. The others are the names of the methods.'
        doc-ref: 'Names'
    instances:
      names:
        value: zzz_names_block.names
  lf_vtshape:
    doc-ref: 'lfVTShape'
    seq:
      - id: count
        type: u2
        doc: 'number of entries in vfunctable'
        doc-ref: 'count'
      - id: descriptors
        type: b4
        enum: tpi::cv_vts_desc
        repeat: expr
        repeat-expr: count
        doc: '4 bit (CV_VTS_desc) descriptors'
        doc-ref: 'desc'
  lf_union:
    doc-ref: 'lfUnion'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: count
        type: u2
        doc: 'count of number of elements in class'
        doc-ref: 'count'
      - id: property
        type: cv_properties
        doc: 'property attribute field'
        doc-ref: 'property'
      - id: field
        type: tpi_type_ref
        doc: 'type index of LF_FIELD descriptor list'
        doc-ref: 'field'
      - id: length
        type: cv_numeric_type
        doc: 'variable length data describing length of structure'
        doc-ref: 'data.length'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'array name'
        doc-ref: 'data.name'
  sym_section:
    doc-ref: 'SECTIONSYM'
    seq:
      - id: section_index
        type: u2
        doc: 'Section number'
        doc-ref: 'isec'
      - id: section_alignment
        type: u1
        doc: 'Alignment of this section (power of 2)'
        doc-ref: 'align'
      - id: reserved
        type: u1
        doc: 'Reserved.  Must be zero.'
        doc-ref: 'bReserved'
      - id: rva
        type: u4
        doc-ref: 'rva'
      - id: size
        type: u4
        doc-ref: 'cb'
      - id: characteristics
        type: u4
        doc-ref: 'characteristics'
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
        doc-ref: 'name'
  sym_function_list:
    doc-ref: 'FUNCTIONLIST'
    seq:
      - id: count
        type: u4
        doc: 'Number of functions'
        doc-ref: 'count'
      - id: functions
        type: tpi_type_ref
        repeat: expr
        repeat-expr: count
        doc: 'List of functions, dim == count'
        doc-ref: 'funcs'
      - id: invocations  
        type: u4
        if: (_io.size - _io.pos) >= 4
        repeat: until
        repeat-until: _io.eof or (_io.size - _io.pos) < 4
        doc: 'array of invocation counts'
        doc-ref: 'invocations'
  sym_reference:
    doc-ref: 'REFSYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: sum_name
        type: u4
        doc: 'SUC of the name'
        doc-ref: 'sumName'
      - id: symbol_offset
        type: u4
        doc: 'Offset of actual symbol in $$Symbols'
        doc-ref: 'ibSym'
      - id: module_index
        type: u2
        doc: 'Module containing the actual symbol'
        doc-ref: 'imod'
      - id: fill
        type: u2
        doc: 'align this record'
        doc-ref: 'usFill'
      - id: name
        type: pdb_string(string_prefixed)
        doc-ref: 'name'
  sym_skip:
    seq:
      - size-eos: true
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
            tpi::leaf_type::lf_vftable: lf_vftable
            tpi::leaf_type::lf_label: lf_label
            _: lf_unknown
      - id: invoke_end_body
        if: end_body_pos >= 0
        size: 0
      # skip any remaining data (when in top-level)
      - id: unparsed_data
        size-eos: true
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
      tpi_version:
        19950410: v40
        19951122: v41
        19960307: v50_beta
        19961031: v50
        19990903: v70
        20040203: v80
      cv_cookietype:
        0: copy
        1: xor_sp
        2: oxr_bp
        3: xor_r13
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
      - id: header16
        if: version.to_i <= tpi::tpi_version::v41.to_i
        type: tpi_header16
      - id: header32
        if: version.to_i > tpi::tpi_version::v41.to_i
        type: tpi_header
      - id: types_data
        size-eos: true
    instances:
      min_type_index:
        value: '(has_header16) ? header16.min_type_index : header32.min_type_index'
      max_type_index:
        value: '(has_header16) ? header16.max_type_index : header32.max_type_index'
      has_header16:
        value: 'version.to_i <= tpi::tpi_version::v41.to_i'
      version:
        pos: 0
        type: u4
        enum: tpi::tpi_version
      types:
        size: 0
        type: tpi_types
        process: cat(types_data)
  dbi_header_flags:
    doc-ref: '_flags'
    seq:
      - id: linked_incrementally
        type: b1
        doc: 'true if linked incrmentally (really just if ilink thunks are present)'
        doc-ref: 'fIncLink'
      - id: stripped
        type: b1
        doc: 'true if PDB::CopyTo stripped the private data out'
        doc-ref: 'fStripped'
      - id: ctypes
        type: b1
        doc: 'true if this PDB is using CTypes.'
        doc-ref: 'fCTypes'
      - id: unused
        type: b13
        doc: 'reserved, must be 0.'
        doc-ref: 'unused'
  symbol_records_stream:
    seq:
      - id: symbols
        type: dbi_symbol(-1)
        repeat: eos
  dbi_header_new:
    doc-ref: 'NewDBIHdr'
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
        doc-ref: 'verSignature'
      - id: version
        type: u4
        enum: version
        doc-ref: 'verHdr'
      - id: age
        type: u4
        doc-ref: 'age'
      - id: gs_symbols_stream
        type: pdb_stream_ref
        doc-ref: 'snGSSyms'
      - id: internal_version
        type: u2
        doc-ref: 'usVerAll'
      - id: ps_symbols_stream
        type: pdb_stream_ref
        doc-ref: 'snPSSyms'
      - id: pdb_dll_version
        type: u2
        doc: 'build version of the pdb dll that built this pdb last.'
        doc-ref: 'usVerPdbDllBuild'
      - id: symbol_records_stream
        type: pdb_stream_ref
        doc-ref: 'snSymRecs'
      - id: rbld_version
        type: u2
        doc: 'rbld version of the pdb dll that built this pdb last.'
        doc-ref: 'usVerPdbDllRBld'
      - id: module_list_size
        type: u4
        doc: 'size of rgmodi substream'
        doc-ref: 'cbGpModi'
      - id: section_contribution_size
        type: u4
        doc: 'size of Section Contribution substream'
        doc-ref: 'cbSC'
      - id: section_map_size
        type: u4
        doc-ref: 'cbSecMap'
      - id: file_info_size
        type: u4
        doc-ref: 'cbFileInfo'
      - id: type_server_map_size
        type: u4
        doc: 'size of the Type Server Map substream'
        doc-ref: 'cbTSMap'
      - id: mfc_type_server_index
        type: u4
        doc: 'index of MFC type server'
        doc-ref: 'iMFC'
      - id: debug_header_size
        type: u4
        doc: 'size of optional DbgHdr info appended to the end of the stream'
        doc-ref: 'cbDbgHdr'
      - id: ec_substream_size
        type: u4
        doc: 'number of bytes in EC substream, or 0 if EC no EC enabled Mods'
        doc-ref: 'cbECInfo'
      - id: flags
        type: dbi_header_flags
        doc-ref: 'flags'
      - id: machine_type
        type: u2
        doc: 'machine type'
        doc-ref: 'wMachine'
      - id: reserved
        type: u4
        doc: 'pad out to 64 bytes for future growth.'
        doc-ref: 'rgulReserved'
    instances:
      symbols_data:
        size: 0
        if: symbol_records_stream.stream_number > -1
        process: cat(symbol_records_stream.data)
        type: symbol_records_stream
      gs_symbols_data:
        size: 0
        if: gs_symbols_stream.stream_number > -1
        process: cat(gs_symbols_stream.data)
        type: global_symbols_stream
      ps_symbols_data:
        size: 0
        if: ps_symbols_stream.stream_number > -1
        process: cat(ps_symbols_stream.data)
        type: public_symbols_stream
  section_contrib40:
    doc-ref: 'SC40'
    seq:
      - id: section_index
        type: u2
        doc-ref: 'isect'
      - id: pad0
        type: u2
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: size
        type: u4
        doc-ref: 'cb'
      - id: characteristics
        type: u4
        doc-ref: 'dwCharacteristics'
      - id: module_index
        type: u2
        doc-ref: 'imod'
      - id: pad1
        type: u2
  section_contrib:
    doc-ref: 'SC'
    seq:
      - id: base
        type: section_contrib40
      - id: data_crc
        type: u4
        doc-ref: 'dwDataCrc'
      - id: reloc_crc
        type: u4
        doc-ref: 'dwRelocCrc'
  section_contrib2:
    doc-ref: 'SC2'
    seq:
      - id: base
        type: section_contrib
      - id: coff_section_index
        type: u4
        doc-ref: 'isectCoff'
  ec_info:
    doc-ref: 'ECInfo'
    seq:
      - id: src_filename_index
        type: u4
        doc: 'NI for src file name'
        doc-ref: 'niSrcFile'
      - id: pdb_filename_index
        type: u4
        doc: 'NI for path to compiler PDB'
        doc-ref: 'niPdbFile'
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
    doc-ref: 'MODI.flags'
    seq:
      - id: written
        type: b1
        doc: 'TRUE if mod has been written since DBI opened'
        doc-ref: 'fWritten'
      - id: ec_enabled
        type: b1
        doc: 'TRUE if mod has EC symbolic information'
        doc-ref: 'fECEnabled'
      - id: unused
        type: b6
        doc: 'spare'
        doc-ref: 'unused'
      - id: tsm_list_index
        type: b8
        doc: 'index into TSM list for this mods server'
        doc-ref: 'iTSM'
  sym_objname:
    doc-ref: 'OBJNAMESYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: signature
        type: u4
        doc: 'signature'
        doc-ref: 'signature'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_compile2_flags:
    doc-ref: 'COMPILESYM.flags'
    seq:
      - id: language
        type: u1
        doc: 'language index'
        doc-ref: 'iLanguage'
      - id: ec
        type: b1
        doc: 'compiled for E/C'
        doc-ref: 'fEC'
      - id: no_dbg_info
        type: b1
        doc: 'not compiled with debug info'
        doc-ref: 'fNoDbgInfo'
      - id: ltcg
        type: b1
        doc: 'compiled with LTCG'
        doc-ref: 'fLTCG'
      - id: no_data_align
        type: b1
        doc: 'compiled with -Bzalign'
        doc-ref: 'fNoDataAlign'
      - id: managed_present
        type: b1
        doc: 'managed code/data present'
        doc-ref: 'fManagedPresent'
      - id: security_checks
        type: b1
        doc: 'compiled with /GS'
        doc-ref: 'fSecurityChecks'
      - id: hot_patch
        type: b1
        doc: 'compiled with /hotpatch'
        doc-ref: 'fHotPatch'
      - id: cvt_cil
        type: b1
        doc: 'converted with CVTCIL'
        doc-ref: 'fCVTCIL'
      - id: msil_module
        type: b1
        doc: 'MSIL netmodule'
        doc-ref: 'fMSILModule'
      - id: pad
        type: b15
        doc: 'reserved, must be 0'
        doc-ref: 'pad'
  sym_compile3_flags:
    doc-ref: 'COMPILESYM3.flags'
    seq:
      - id: language
        type: u1
        doc: 'language index'
        doc-ref: 'iLanguage'
      - id: ec
        type: b1
        doc: 'compiled for E/C'
        doc-ref: 'fEC'
      - id: no_dbg_info
        type: b1
        doc: 'not compiled with debug info'
        doc-ref: 'fNoDbgInfo'
      - id: ltcg
        type: b1
        doc: 'compiled with LTCG'
        doc-ref: 'fLTCG'
      - id: no_data_align
        type: b1
        doc: 'compiled with -Bzalign'
        doc-ref: 'fNoDataAlign'
      - id: managed_present
        type: b1
        doc: 'managed code/data present'
        doc-ref: 'fManagedPresent'
      - id: security_checks
        type: b1
        doc: 'compiled with /GS'
        doc-ref: 'fSecurityChecks'
      - id: hot_patch
        type: b1
        doc: 'compiled with /hotpatch'
        doc-ref: 'fHotPatch'
      - id: cvt_cil
        type: b1
        doc: 'converted with CVTCIL'
        doc-ref: 'fCVTCIL'
      - id: msil_module
        type: b1
        doc: 'MSIL netmodule'
        doc-ref: 'fMSILModule'
      - id: sdl
        type: b1
        doc: 'compiled with /sdl'
        doc-ref: 'fSdl'
      - id: pgo
        type: b1
        doc: 'compiled with /ltcg:pgo or pgu'
        doc-ref: 'fPGO'
      - id: exp
        type: b1
        doc: '.exp module'
        doc-ref: 'fExp'
      - id: pad
        type: b12
        doc: 'reserved, must be 0'
        doc-ref: 'pad'
  sym_compile3:
    doc-ref: 'COMPILESYM3'
    seq:
      - id: flags
        type: sym_compile3_flags
        doc-ref: 'flags'
      - id: machine
        type: u2
        doc: 'target processor'
        doc-ref: 'machine'
      - id: ver_fe_major
        type: u2
        doc: 'front end major version #'
        doc-ref: 'verFEMajor'
      - id: ver_fe_minor
        type: u2
        doc: 'front end minor version #'
        doc-ref: 'verFEMinor'
      - id: ver_fe_build
        type: u2
        doc: 'front end build version #'
        doc-ref: 'verFEBuild'
      - id: ver_fe_qfe
        type: u2
        doc: 'front end QFE version #'
        doc-ref: 'verFEQFE'
      - id: ver_major
        type: u2
        doc: 'back end major version #'
        doc-ref: 'verMajor'
      - id: ver_minor
        type: u2
        doc: 'back end minor version #'
        doc-ref: 'verMinor'
      - id: ver_build
        type: u2
        doc: 'back end build version #'
        doc-ref: 'verBuild'
      - id: ver_qfe
        type: u2
        doc: 'back end QFE version #'
        doc-ref: 'verQFE'
      - id: version_string
        type: pdb_string(false)
        doc: 'Zero terminated compiler version string'
        doc-ref: 'verSz'
  sym_compile2:
    doc-ref: 'COMPILESYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: flags
        type: sym_compile2_flags
        doc: 'flags'
        doc-ref: 'flags'
      - id: machine
        type: u2
        doc: 'target processor'
        doc-ref: 'machine'
      - id: ver_fe_major
        type: u2
        doc: 'front end major version #'
        doc-ref: 'verFEMajor'
      - id: ver_fe_minor
        type: u2
        doc: 'front end minor version #'
        doc-ref: 'verFEMinor'
      - id: ver_fe_build
        type: u2
        doc: 'front end build version #'
        doc-ref: 'verFEBuild'
      - id: ver_major
        type: u2
        doc: 'back end major version #'
        doc-ref: 'verMajor'
      - id: ver_minor
        type: u2
        doc: 'back end minor version #'
        doc-ref: 'verMinor'
      - id: ver_build
        type: u2
        doc: 'back end build version #'
        doc-ref: 'verBuild'
      - id: version_string
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed compiler version string'
        doc-ref: 'verSt'
      - id: strings_block
        type: str
        encoding: UTF-8
        terminator: 0
        repeat: until
        repeat-until: _ == ""
        doc: 'an optional block of zero terminated strings, terminated with a double zero.'
  sym_compile:
    doc-ref: 'CFLAGSYM'
    seq:
      - id: machine
        type: u1
        doc: 'target processor'
        doc-ref: 'machine'
      - id: language
        type: u1
        doc: 'language index'
        doc-ref: 'language'
      - id: pcode
        type: b1
        doc: 'true if pcode present'
        doc-ref: 'pcode'
      - id: floatprec
        type: b2
        doc: 'floating precision'
        doc-ref: 'floatprec'
      - id: floatpkg
        type: b2
        doc: 'float package'
        doc-ref: 'floatpkg'
      - id: ambdata
        type: b3
        doc: 'ambient data model'
        doc-ref: 'ambdata'
      - id: ambcode
        type: b3
        doc: 'ambient code model'
        doc-ref: 'ambcode'
      - id: mode32
        type: b1
        doc: 'true if compiled 32 bit mode'
        doc-ref: 'mode32'
      - id: pad
        type: b4
        doc: 'reserved'
        doc-ref: 'pad'
      - id: version_string
        type: pdb_string(true)
        doc: 'Length-prefixed compiler version string'
        doc-ref: 'ver'
  sym_constant:
    doc-ref: 'CONSTSYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index (containing enum if enumerate) or metadata token'
        doc-ref: 'typind'
      - id: value
        type: cv_numeric_type
        doc: 'numeric leaf containing value'
        doc-ref: 'value'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_udt:
    doc-ref: 'UDTSYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
        doc-ref: 'typind'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_unamespace:
    doc-ref: 'UNAMESPACE'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'name'
        doc-ref: 'name'
  sym_frame_cookie:
    doc-ref: 'FRAMECOOKIE'
    seq:
      - id: offset
        type: u4
        doc: 'Frame relative offset'
        doc-ref: 'off'
      - id: register
        type: u2
        doc: 'Register index'
        doc-ref: 'reg'
      - id: cookie_type
        type: u1
        enum: tpi::cv_cookietype
        doc: 'Type of the cookie'
        doc-ref: 'cookietype'
      - id: flags
        type: u1
        doc: 'Flags describing this cookie'
        doc-ref: 'flags'
  cv_lvar_attr:
    doc-ref: 'CV_lvar_attr'
    seq:
      - id: offset
        type: u4
        doc: 'first code address where var is live'
        doc-ref: 'off'
      - id: segment
        type: u2
        doc-ref: 'seg'
      - id: flags
        type: cv_local_var_flags
        doc: 'local var flags'
        doc-ref: 'flags'
  sym_attr_slot:
    doc-ref: 'ATTRSLOTSYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: slot_index
        type: u4
        doc: 'slot index'
        doc-ref: 'iSlot'
      - id: type
        type: tpi_type_ref
        doc: 'Type index or Metadata token'
        doc-ref: 'typind'
      - id: attr
        type: cv_lvar_attr
        doc: 'local var attributes'
        doc-ref: 'attr'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_annotation:
    doc-ref: 'ANNOTATIONSYM'
    seq:
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: segment
        type: u2
        doc-ref: 'seg'
      - id: num_strings
        type: u2
        doc: 'Count of zero terminated annotation strings'
        doc-ref: 'csz'
      - id: strings
        type: str
        encoding: UTF-8
        terminator: 0
        repeat: expr
        repeat-expr: num_strings
        doc: 'Sequence of zero terminated annotation strings'
        doc-ref: 'rgsz'
  sym_frame_proc_flags:
    doc-ref: 'FRAMEPROCSYM.flags'
    seq:
      - id: has_alloca
        type: b1
        doc: 'function uses _alloca()'
        doc-ref: 'fHasAlloca'
      - id: has_setjmp
        type: b1
        doc: 'function uses setjmp()'
        doc-ref: 'fHasSetJmp'
      - id: has_longjmp
        type: b1
        doc: 'function uses longjmp()'
        doc-ref: 'fHasLongJmp'
      - id: has_inline_asm
        type: b1
        doc: 'function uses inline asm'
        doc-ref: 'fHasInlAsm'
      - id: has_eh
        type: b1
        doc: 'function has EH states'
        doc-ref: 'fHasEH'
      - id: inline_spec
        type: b1
        doc: 'function was speced as inline'
        doc-ref: 'fInlSpec'
      - id: has_seh
        type: b1
        doc: 'function has SEH'
        doc-ref: 'fHasSEH'
      - id: naked
        type: b1
        doc: 'function is __declspec(naked)'
        doc-ref: 'fNaked'
      - id: security_checks
        type: b1
        doc: 'function has buffer security check introduced by /GS.'
        doc-ref: 'fSecurityChecks'
      - id: async_eh
        type: b1
        doc: 'function compiled with /EHa'
        doc-ref: 'fAsyncEH'
      - id: gs_no_stack_ordering
        type: b1
        doc: 'function has /GS buffer checks, but stack ordering couldn''t be done'
        doc-ref: 'fGSNoStackOrdering'
      - id: was_inlined
        type: b1
        doc: 'function was inlined within another function'
        doc-ref: 'fWasInlined'
      - id: gs_check
        type: b1
        doc: 'function is __declspec(strict_gs_check)'
        doc-ref: 'fGSCheck'
      - id: safe_buffers
        type: b1
        doc: 'function is __declspec(safebuffers)'
        doc-ref: 'fSafeBuffers'
      - id: encoded_local_base_pointer
        type: b2
        doc: 'record function''s local pointer explicitly.'
        doc-ref: 'encodedLocalBasePointer'
      - id: encoded_param_base_pointer
        type: b2
        doc: 'record function''s parameter pointer explicitly.'
        doc-ref: 'encodedParamBasePointer'
      - id: pogo_on
        type: b1
        doc: 'function was compiled with PGO/PGU'
        doc-ref: 'fPogoOn'
      - id: valid_counts
        type: b1
        doc: 'Do we have valid Pogo counts?'
        doc-ref: 'fValidCounts'
      - id: opt_speed
        type: b1
        doc: 'Did we optimize for speed?'
        doc-ref: 'fOptSpeed'
      - id: guard_cf
        type: b1
        doc: 'function contains CFG checks (and no write checks)'
        doc-ref: 'fGuardCF'
      - id: guard_cfw
        type: b1
        doc: 'function contains CFW checks and/or instrumentation'
        doc-ref: 'fGuardCFW'
      - id: pad
        type: b9
        doc: 'must be zero'
        doc-ref: 'pad'
  sym_frame_proc:
    doc-ref: 'FRAMEPROCSYM'
    seq:
      - id: frame_size
        type: u4
        doc: 'count of bytes of total frame of procedure'
        doc-ref: 'cbFrame'
      - id: pad_size
        type: u4
        doc: 'count of bytes of padding in the frame'
        doc-ref: 'cbPad'
      - id: pad_offset
        type: u4
        doc: 'offset (relative to frame poniter) to where padding starts'
        doc-ref: 'offPad'
      - id: save_regs_size
        type: u4
        doc: 'count of bytes of callee save registers'
        doc-ref: 'cbSaveRegs'
      - id: exception_handler_offset
        type: u4
        doc: 'offset of exception handler'
        doc-ref: 'offExHdlr'
      - id: exception_handler_section
        type: u2
        doc: 'section id of exception handler'
        doc-ref: 'sectExHdlr'
      - id: flags
        type: sym_frame_proc_flags
        doc-ref: 'flags'
  sym_label32:
    doc-ref: 'LABELSYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: segment
        type: u2
        doc-ref: 'seg'
      - id: flags
        type: cv_proc_flags
        doc: 'flags'
        doc-ref: 'flags'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_data_hlsl:
    doc-ref: 'DATASYMHLSL'
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
        doc-ref: 'typind'
      - id: reg_type
        type: u2
        doc: 'register type from CV_HLSLREG_e'
        doc-ref: 'regType'
      - id: data_slot
        type: u2
        doc: 'Base data (cbuffer, groupshared, etc.) slot'
        doc-ref: 'dataslot'
      - id: data_offset
        type: u2
        doc: 'Base data byte offset start'
        doc-ref: 'dataoff'
      - id: tex_slot
        type: u2
        doc: 'Texture slot start'
        doc-ref: 'texslot'
      - id: samp_slot
        type: u2
        doc: 'Sampler slot start'
        doc-ref: 'sampslot'
      - id: uav_slot
        type: u2
        doc: 'UAV slot start'
        doc-ref: 'uavslot'
      - id: name
        type: str
        terminator: 0
        encoding: UTF-8
        doc: 'name'
        doc-ref: 'name'
  sym_data_hlsl32:
    doc-ref: 'DATASYMHLSL32'
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
        doc-ref: 'typind'
      - id: data_slot
        type: u4
        doc: 'Base data (cbuffer, groupshared, etc.) slot'
        doc-ref: 'dataslot'
      - id: data_offset
        type: u4
        doc: 'Base data byte offset start'
        doc-ref: 'dataoff'
      - id: tex_slot
        type: u4
        doc: 'Texture slot start'
        doc-ref: 'texslot'
      - id: samp_slot
        type: u4
        doc: 'Sampler slot start'
        doc-ref: 'sampslot'
      - id: uav_slot
        type: u4
        doc: 'UAV slot start'
        doc-ref: 'uavslot'
      - id: reg_type
        type: u4
        doc: 'register type from CV_HLSLREG_e'
        doc-ref: 'regType'
      - id: name
        type: str
        terminator: 0
        encoding: UTF-8
        doc: 'name'
        doc-ref: 'name'
  sym_data_hlsl32_ex:
    doc-ref: 'DATASYMHLSL32_EX'
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
        doc-ref: 'typind'
      - id: reg_id
        type: u4
        doc: 'Register index'
        doc-ref: 'regID'
      - id: data_off
        type: u4
        doc: 'Base data byte offset start'
        doc-ref: 'dataoff'
      - id: bind_space
        type: u4
        doc: 'Binding space'
        doc-ref: 'bindSpace'
      - id: bind_slot
        type: u4
        doc: 'Lower bound in binding space'
        doc-ref: 'bindSlot'
      - id: reg_type
        type: u2
        doc: 'register type from CV_HLSLREG_e'
        doc-ref: 'regType'
      - id: name
        type: str
        terminator: 0
        encoding: UTF-8
        doc: 'name'
        doc-ref: 'name'
  sym_register32:
    doc-ref: 'REGSYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
        doc-ref: 'typind'
      - id: register
        type: u2
        doc: 'register enumerate'
        doc-ref: 'reg'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_bprel32:
    doc-ref: 'BPRELSYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: offset
        type: u4
        doc: 'BP-relative offset'
        doc-ref: 'off'
      - id: type
        type: tpi_type_ref
        doc: 'Type index or Metadata token'
        doc-ref: 'typind'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_data32:
    doc-ref: 'DATASYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'Type index, or Metadata token if a managed symbol'
        doc-ref: 'typind'
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: segment
        type: u2
        doc-ref: 'seg'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_with32:
    doc-ref: 'WITHSYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
        doc-ref: 'pParent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
        doc-ref: 'pEnd'
      - id: length
        type: u4
        doc: 'Block length'
        doc-ref: 'len'
      - id: offset
        type: u4
        doc: 'Offset in code segment'
        doc-ref: 'off'
      - id: segment
        type: u2
        doc: 'segment of label'
        doc-ref: 'seg'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed expression string'
        doc-ref: 'name'
  sym_block32:
    doc-ref: 'BLOCKSYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
        doc-ref: 'pParent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
        doc-ref: 'pEnd'
      - id: length
        type: u4
        doc: 'Block length'
        doc-ref: 'len'
      - id: offset
        type: u4
        doc: 'Offset in code segment'
        doc-ref: 'off'
      - id: segment
        type: u2
        doc: 'segment of label'
        doc-ref: 'seg'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_regrel32:
    doc-ref: 'REGREL32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: offset
        type: u4
        doc: 'offset of symbol'
        doc-ref: 'off'
      - id: type
        type: tpi_type_ref
        doc: 'Type index or metadata token'
        doc-ref: 'typind'
      - id: register
        type: u2
        doc: 'register index for symbol'
        doc-ref: 'reg'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_thread32:
    doc-ref: 'THREADSYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'type index'
        doc-ref: 'typind'
      - id: offset
        type: u4
        doc: 'offset into thread storage'
        doc-ref: 'off'
      - id: segment
        type: u2
        doc: 'segment of thread storage'
        doc-ref: 'seg'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'length prefixed name'
        doc-ref: 'name'
  sym_manproc:
    doc-ref: 'MANPROCSYM'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
        doc-ref: 'pParent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
        doc-ref: 'pEnd'
      - id: next
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to next symbol'
        doc-ref: 'pNext'
      - id: length
        type: u4
        doc: 'Proc length'
        doc-ref: 'len'
      - id: dbg_start
        type: u4
        doc: 'Debug start offset'
        doc-ref: 'DbgStart'
      - id: dbg_end
        type: u4
        doc: 'Debug end offset'
        doc-ref: 'DbgEnd'
      - id: token
        type: u4
        doc: 'COM+ metadata token for method'
        doc-ref: 'token'
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: segment
        type: u2
        doc-ref: 'seg'
      - id: flags
        type: cv_proc_flags
        doc: 'Proc flags'
        doc-ref: 'flags'
      - id: return_register
        type: u2
        doc: 'Register return value is in (may not be used for all archs)'
        doc-ref: 'retReg'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'optional name field'
        doc-ref: 'name'
  sym_proc32:
    doc-ref: 'PROCSYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
        doc-ref: 'pParent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
        doc-ref: 'pEnd'
      - id: next
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to next symbol'
        doc-ref: 'pNext'
      - id: length
        type: u4
        doc: 'Proc length'
        doc-ref: 'len'
      - id: dbg_start
        type: u4
        doc: 'Debug start offset'
        doc-ref: 'DbgStart'
      - id: dbg_end
        type: u4
        doc: 'Debug end offset'
        doc-ref: 'DbgEnd'
      # FIXME: ID handling
      - id: type
        type: tpi_type_ref
        doc: 'Type index or ID'
        doc-ref: 'typind'
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: segment
        type: u2
        doc-ref: 'seg'
      - id: flags
        type: cv_proc_flags
        doc-ref: 'flags'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
  sym_envblock_flags:
    doc-ref: 'ENVBLOCKSYM.flags'
    seq:
      - id: rev
        type: b1
        doc: 'reserved'
        doc-ref: 'rev'
      - id: pad
        type: b7
        doc: 'reserved, must be 0'
        doc-ref: 'pad'
  sym_envblock:
    doc-ref: 'ENVBLOCKSYM'
    seq:
      - id: flags
        type: sym_envblock_flags
        doc-ref: 'flags'
      - id: strings
        type: str
        encoding: UTF-8
        repeat: eos
        terminator: 0
        doc: 'Sequence of zero-terminated strings'
        doc-ref: 'rgsz'
  sym_thunk32:
    doc-ref: 'THUNKSYM32'
    params:
      - id: string_prefixed
        type: bool
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
        doc-ref: 'pParent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
        doc-ref: 'pEnd'
      - id: next
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to next symbol'
        doc-ref: 'pNext'
      - id: offset
        type: u4
        doc-ref: 'off'
      - id: segment
        type: u2
        doc-ref: 'seg'
      - id: length
        type: u2
        doc: 'length of thunk'
        doc-ref: 'len'
      - id: ordinal
        type: u1
        doc: 'ordinal specifying type of thunk'
        doc-ref: 'ord'
      - id: name
        type: pdb_string(string_prefixed)
        doc: 'Length-prefixed name'
        doc-ref: 'name'
      # FIXME
      - id: variant
        size-eos: true
        doc: 'variant portion of thunk'
        doc-ref: 'variant'
  sym_arm_switch_table:
    doc-ref: 'ARMSWITCHTABLE'
    seq:
      - id: offset_base
        type: u4
        doc: 'Section-relative offset to the base for switch offsets'
        doc-ref: 'offsetBase'
      - id: base_section
        type: u2
        doc: 'Section index of the base for switch offsets'
        doc-ref: 'sectBase'
      - id: switch_type
        type: u2
        doc: 'type of each entry'
        doc-ref: 'switchType'
      - id: offset_branch
        type: u4
        doc: 'Section-relative offset to the table branch instruction'
        doc-ref: 'offsetBranch'
      - id: offset_table
        type: u4
        doc: 'Section-relative offset to the start of the table'
        doc-ref: 'offsetTable'
      - id: branch_section
        type: u2
        doc: 'Section index of the table branch instruction'
        doc-ref: 'sectBranch'
      - id: table_section
        type: u2
        doc: 'Section index of the table'
        doc-ref: 'sectTable'
      - id: num_entries 
        type: u4
        doc: 'number of switch table entries'
        doc-ref: 'cEntries'
  cv_local_var_flags:
    doc-ref: 'CV_LVARFLAGS'
    seq:
      - id: is_param
        type: b1
        doc: 'variable is a parameter'
        doc-ref: 'fIsParam'
      - id: addr_taken
        type: b1
        doc: 'address is taken'
        doc-ref: 'fAddrTaken'
      - id: comp_genx
        type: b1
        doc: 'variable is compiler generated'
        doc-ref: 'fCompGenx'
      - id: is_aggregate
        type: b1
        doc: 'the symbol is splitted in temporaries, which are treated by compiler as independent entities'
        doc-ref: 'fIsAggregate'
      - id: is_aggregated
        type: b1
        doc: 'Counterpart of fIsAggregate - tells that it is a part of a fIsAggregate symbol'
        doc-ref: 'fIsAggregated'
      - id: is_aliased
        type: b1
        doc: 'variable has multiple simultaneous lifetimes'
        doc-ref: 'fIsAliased'
      - id: is_alias
        type: b1
        doc: 'represents one of the multiple simultaneous lifetimes'
        doc-ref: 'fIsAlias'
      - id: is_return_value
        type: b1
        doc: 'represents a function return value'
        doc-ref: 'fIsRetValue'
      - id: is_optimized_out
        type: b1
        doc: 'variable has no lifetimes'
        doc-ref: 'fIsOptimizedOut'
      - id: is_enregistered_global
        type: b1
        doc: 'variable is an enregistered global'
        doc-ref: 'fIsEnregGlob'
      - id: is_enregistered_static
        type: b1
        doc: 'variable is an enregistered static'
        doc-ref: 'fIsEnregStat'
      - id: unused
        type: b5
        doc: 'must be zero'
        doc-ref: 'unused'
  sym_local:
    doc-ref: 'LOCALSYM'
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'type index'
        doc-ref: 'typind'
      - id: flags
        type: cv_local_var_flags
        doc: 'local var flags'
        doc-ref: 'flags'
  sym_build_info:
    doc-ref: 'BUILDINFOSYM'
    # FIXME: CV_ItemID (DEBUG_S_CROSSSCOPEIMPORTS)
    seq:
      - id: id
        type: u4
        doc: 'CV_ItemId of Build Info.'
        doc-ref: 'id'
  sym_heap_alloc_site:
    doc-ref: 'HEAPALLOCSITE'
    seq:
      - id: off
        type: u4
        doc: 'offset of call site'
        doc-ref: 'off'
      - id: section
        type: u2
        doc: 'section index of call site'
        doc-ref: 'sect'
      - id: instruction_size
        type: u2
        doc: 'length of heap allocation call instruction'
        doc-ref: 'cbInstr'
      - id: type
        type: tpi_type_ref
        doc: 'type index describing function signature'
        doc-ref: 'typind'
  sym_callsite_info:
    doc-ref: 'CALLSITEINFO'
    seq:
      - id: offset
        type: u4
        doc: 'offset of call site'
        doc-ref: 'off'
      - id: section
        type: u2
        doc: 'section index of call site'
        doc-ref: 'sect'
      - size: 2
        doc: 'alignment padding field, must be zero'
        doc-ref: '__reserved_0'
      - id: type
        type: tpi_type_ref
        doc: 'type index describing function signature'
        doc-ref: 'typind'
  sym_file_static:
    doc-ref: 'FILESTATICSYM'
    seq:
      - id: type
        type: tpi_type_ref
        doc: 'type index'
        doc-ref: 'typind'
      # TODO: this refers to a string. 
      # the offset is relative to the symbol beginning
      # in the parent module stream
      - id: mod_offset
        type: u4
        doc: 'index of mod filename in stringtable'
        doc-ref: 'modOffset'
      - id: flags
        type: cv_local_var_flags
        doc: 'local var flags'
        doc-ref: 'flags'
      - id: name
        type: str
        encoding: UTF-8
        terminator: 0
        doc: 'Name of this symbol, a null terminated array of UTF8 characters'
        doc-ref: 'name'
  sym_inline_site:
    doc-ref: 'INLINESITESYM'
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the inliner'
        doc-ref: 'pParent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end'
        doc-ref: 'pEnd'
      - id: inlinee
        type: u4
        doc: 'CV_ItemId of inlinee' #FIXME
        doc-ref: 'inlinee'
      - id: binary_annotations #FIXME
        size-eos: true
        doc: 'an array of compressed binary annotations.' 
        doc-ref: 'binaryAnnotations'
  cv_range_attr:
    doc-ref: 'CV_RANGEATTR'
    seq:
      - id: maybe
        type: b1
        doc: 'May have no user name on one of control flow path.'
        doc-ref: 'maybe'
      - id: padding
        type: b15
        doc: 'Padding for future use.'
        doc-ref: 'padding'
  cv_lvar_addr_range:
    doc: 'defines a range of addresses'
    doc-ref: 'CV_LVAR_ADDR_RANGE'
    seq:
      - id: offset_start
        type: u4
        doc-ref: 'offStart'
      - id: section_start_index
        type: u2
        doc-ref: 'isectStart'
      - id: range_length
        type: u2 # in bytes
        doc-ref: 'cbRange'
  cv_lvar_addr_gap:
    doc-ref: 'CV_LVAR_ADDR_GAP'
    doc: 'Represents the holes in overall address range, all address is pre-bbt. it is for compress and reduce the amount of relocations need.'
    seq:
      - id: gap_start_offset
        type: u2
        doc: 'relative offset from the beginning of the live range.'
        doc-ref: 'gapStartOffset'
      - id: gap_length
        type: u2
        doc: 'length of this gap.'
        doc-ref: 'cbRange'
  sym_defrange_register_rel:
    doc-ref: 'DEFRANGESYMREGISTERREL'
    seq:
      - id: base_register
        type: u2
        doc: 'Register to hold the base pointer of the symbol'
        doc-ref: 'baseReg'
      - id: spilled_udt_member
        type: b1
        doc: 'Spilled member for s.i.'
        doc-ref: 'spilledUdtMember'
      - type: b3
        doc: 'Padding for future use.'
        doc-ref: 'padding'
      - id: offset_member
        type: b12
        doc: 'Offset in parent variable.'
        doc-ref: 'offsetParent'
      - id: base_pointer_offset
        type: u4
        doc: 'offset to register'
        doc-ref: 'offBasePointer'
      - id: range
        type: cv_lvar_addr_range
        doc: 'Range of addresses where this program is valid'
        doc-ref: 'range'
      - id: gaps
        type: cv_lvar_addr_gap
        repeat: eos
        doc: 'The value is not available in following gaps.'
        doc-ref: 'gaps'
  sym_defrange_register:
    doc-ref: 'DEFRANGESYMREGISTER'
    seq:
      - id: reg
        type: u2
        doc: 'Register to hold the value of the symbol'
      - id: attr
        type: cv_range_attr
        doc: 'Attribute of the register range.'
      - id: range
        type: cv_lvar_addr_range
        doc: 'Range of addresses where this program is valid'
      - id: gaps
        type: cv_lvar_addr_gap
        repeat: eos
  sym_defrange_framepointer_rel:
    doc-ref: 'DEFRANGESYMFRAMEPOINTERREL'
    params:
      - id: full_scope
        type: bool
        doc-ref: 'DEFRANGESYMFRAMEPOINTERREL_FULL_SCOPE'
    seq:
      - id: frame_pointer_offset
        type: u4
        doc: 'offset to frame pointer'
        doc-ref: 'offFramePointer'
      - id: range
        if: full_scope == false
        type: cv_lvar_addr_range
        doc: 'Range of addresses where this program is valid'
        doc-ref: 'range'
      - id: gaps
        if: full_scope == false
        repeat: eos
        type: cv_lvar_addr_gap
        doc: 'The value is not available in following gaps. '
        doc-ref: 'gaps'
  sym_defrange_subfield_register:
    doc-ref: 'DEFRANGESYMSUBFIELDREGISTER'
    seq:
      - id: register
        type: u2
        doc: 'Register to hold the value of the symbol'
        doc-ref: 'reg'
      - id: attr
        type: cv_range_attr
        doc: 'Attribute of the register range.'
        doc-ref: 'attr'
      - id: parent_offset
        type: b12
        doc: 'Offset in parent variable.'
        doc-ref: 'offParent'
      - type: b20
        doc: 'Padding for future use.'
        doc-ref: 'padding'
      - id: range
        type: cv_lvar_addr_range
        doc: 'Range of addresses where this program is valid'
        doc-ref: 'range'
      - id: gaps
        repeat: eos
        type: cv_lvar_addr_gap
        doc: 'The value is not available in following gaps. '
        doc-ref: 'gaps'
  sym_coff_group:
    doc-ref: 'COFFGROUPSYM'
    seq:
      - id: size
        type: u4
        doc: 'cb'
        doc-ref: 'cb'
      - id: characteristics
        type: u4
        doc-ref: 'characteristics'
      - id: symbol_offset
        type: u4
        doc: 'Symbol offset'
        doc-ref: 'off'
      - id: symbol_segment
        type: u2
        doc: 'Symbol segment'
        doc-ref: 'seg'
      - id: name
        type: pdb_string(false)
        doc: 'name'
        doc-ref: 'name'
  sym_export:
    doc-ref: 'EXPORTSYM'
    seq:
      - id: ordinal
        type: u2
        doc-ref: 'ordinal'
      - id: is_constant
        type: b1
        doc: 'CONSTANT'
        doc-ref: 'fConstant'
      - id: is_data
        type: b1
        doc: 'DATA'
        doc-ref: 'fData'
      - id: is_private
        type: b1
        doc: 'PRIVATE'
        doc-ref: 'fPrivate'
      - id: is_noname
        type: b1
        doc: 'NONAME'
        doc-ref: 'fNoName'
      - id: is_ordinal
        type: b1
        doc: 'Ordinal was explicitly assigned'
        doc-ref: 'fOrdinal'
      - id: is_forwarder
        type: b1
        doc: 'This is a forwarder'
        doc-ref: 'fForwarder'
      - id: reserved
        type: b10
        doc: 'Reserved. Must be zero.'
        doc-ref: 'reserved'
      - id: name
        doc: 'name of'
        type: str
        encoding: UTF-8
        terminator: 0
        doc-ref: 'name'
  sym_trampoline:
    doc-ref: 'TRAMPOLINESYM'
    seq:
      - id: trampoline_type
        type: u2
        doc: 'trampoline sym subtype'
        doc-ref: 'trampType'
      - id: thunk_size
        type: u2
        doc: 'size of the thunk'
        doc-ref: 'cbThunk'
      - id: thunk_offset
        type: u4
        doc: 'offset of the thunk'
        doc-ref: 'offThunk'
      - id: thunk_target_offset
        type: u4
        doc: 'offset of the target of the thunk'
        doc-ref: 'offTarget'
      - id: thunk_section_index
        type: u2
        doc: 'section index of the thunk'
        doc-ref: 'sectThunk'
      - id: thunk_target_section_index
        type: u2
        doc: 'section index of the target of the thunk'
        doc-ref: 'sectTarget'
  sym_oem:
    doc-ref: 'OEMSYMBOL'
    seq:
      - id: oem_id
        size: 16
        doc: 'an oem ID (GUID)'
        doc-ref: 'idOem'
      - id: type
        type: tpi_type_ref
        doc: 'Type index'
        doc-ref: 'typind'
      - id: user_data
        size-eos: true
        doc: 'user data, force 4-byte alignment'
        doc-ref: 'rgl'
  cv_sepcode_flags:
    doc: 'flag bitfields for separated code attributes'
    doc-ref: 'CV_SEPCODEFLAGS'
    seq:
      - id: is_lexical_scope
        type: b1
        doc: 'S_SEPCODE doubles as lexical scope'
        doc-ref: 'fIsLexicalScope'
      - id: returns_to_parent
        type: b1
        doc: 'code frag returns to parent'
        doc-ref: 'fReturnsToParent'
      - id: pad
        type: b30
        doc: 'must be zero'
        doc-ref: 'pad'
  sym_sepcode:
    seq:
      - id: parent
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to the parent'
        doc-ref: 'pParent'
      - id: end
        type: dbi_symbol_ref(_parent.module_index)
        doc: 'pointer to this blocks end' 
        doc-ref: 'pEnd'
      - id: length
        type: u4
        doc: 'count of bytes of this block'
        doc-ref: 'length'
      - id: scf
        type: cv_sepcode_flags
        doc: 'flags'
        doc-ref: 'scf'
      - id: offset
        type: u4
        doc: 'sect:off of the separated code'
        doc-ref: 'off'
      - id: parent_offset
        type: u4
        doc: 'sectParent:offParent of the enclosing scope'
        doc-ref: 'offParent'
      - id: section
        type: u2
        doc: '(proc, block, or sepcode)'
        doc-ref: 'sect'
      - id: parent_section
        type: u2
        doc-ref: 'sectParent'
  dbi_symbol_ref:
    params:
      - id: module_index
        type: u4
    seq:
      # data offset
      - id: offset
        type: u4
    instances:
      zzz_module_io:
        type: get_module_io(module_index)
      module_io:
        value: zzz_module_io.value
      is_offset_eof:
        value: offset >= module_io.size
      symbol:
        io: module_io
        if: is_offset_eof == false
        # go before length field
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
            dbi::symbol_type::s_compile2: sym_compile2(false)
            dbi::symbol_type::s_compile2_st: sym_compile2(true)
            dbi::symbol_type::s_compile3: sym_compile3
            dbi::symbol_type::s_constant: sym_constant(false)
            dbi::symbol_type::s_constant_st: sym_constant(true)
            dbi::symbol_type::s_udt: sym_udt(false)
            dbi::symbol_type::s_coboludt: sym_udt(false)
            dbi::symbol_type::s_udt_st: sym_udt(true)
            dbi::symbol_type::s_coboludt_st: sym_udt(true)
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
            dbi::symbol_type::s_with32: sym_with32(false)
            dbi::symbol_type::s_with32_st: sym_with32(true)
            dbi::symbol_type::s_ldata32: sym_data32(false)
            dbi::symbol_type::s_ldata32_st: sym_data32(true)
            dbi::symbol_type::s_gdata32: sym_data32(false)
            dbi::symbol_type::s_gdata32_st: sym_data32(true)
            dbi::symbol_type::s_pub32: sym_data32(false)
            dbi::symbol_type::s_pub32_st: sym_data32(true)
            dbi::symbol_type::s_thunk32: sym_thunk32(false)
            dbi::symbol_type::s_thunk32_st: sym_thunk32(true)
            dbi::symbol_type::s_section: sym_section
            dbi::symbol_type::s_annotation: sym_annotation
            dbi::symbol_type::s_framecookie: sym_frame_cookie
            dbi::symbol_type::s_frameproc: sym_frame_proc
            dbi::symbol_type::s_envblock: sym_envblock
            dbi::symbol_type::s_unamespace_st: sym_unamespace(true)
            dbi::symbol_type::s_unamespace: sym_unamespace(false)
            dbi::symbol_type::s_callers: sym_function_list
            dbi::symbol_type::s_callees: sym_function_list
            dbi::symbol_type::s_inlinees: sym_function_list
            dbi::symbol_type::s_skip: sym_skip
            dbi::symbol_type::s_armswitchtable: sym_arm_switch_table
            dbi::symbol_type::s_filestatic: sym_file_static
            dbi::symbol_type::s_buildinfo: sym_build_info
            dbi::symbol_type::s_heapallocsite: sym_heap_alloc_site
            dbi::symbol_type::s_block32_st: sym_block32(true)
            dbi::symbol_type::s_block32: sym_block32(false)
            dbi::symbol_type::s_lthread32_st: sym_thread32(true)
            dbi::symbol_type::s_lthread32: sym_thread32(false)
            dbi::symbol_type::s_gthread32_st: sym_thread32(true)
            dbi::symbol_type::s_gthread32: sym_thread32(false)
            dbi::symbol_type::s_callsiteinfo: sym_callsite_info
            dbi::symbol_type::s_local: sym_local
            dbi::symbol_type::s_regrel32: sym_regrel32(false)
            dbi::symbol_type::s_regrel32_st: sym_regrel32(true)
            dbi::symbol_type::s_inlinesite: sym_inline_site
            dbi::symbol_type::s_coffgroup: sym_coff_group
            dbi::symbol_type::s_defrange_register: sym_defrange_register
            dbi::symbol_type::s_defrange_register_rel: sym_defrange_register_rel
            dbi::symbol_type::s_defrange_subfield_register: sym_defrange_subfield_register
            dbi::symbol_type::s_defrange_framepointer_rel: sym_defrange_framepointer_rel(false)
            dbi::symbol_type::s_defrange_framepointer_rel_full_scope: sym_defrange_framepointer_rel(true)
            dbi::symbol_type::s_export: sym_export
            dbi::symbol_type::s_trampoline: sym_trampoline
            dbi::symbol_type::s_oem: sym_oem
            dbi::symbol_type::s_gmanproc: sym_manproc(false)
            dbi::symbol_type::s_gmanproc_st: sym_manproc(true)
            dbi::symbol_type::s_lmanproc: sym_manproc(false)
            dbi::symbol_type::s_lmanproc_st: sym_manproc(true)
            dbi::symbol_type::s_manslot: sym_attr_slot(false)
            dbi::symbol_type::s_manslot_st: sym_attr_slot(true)
            dbi::symbol_type::s_sepcode: sym_sepcode
            dbi::symbol_type::s_procref_st: sym_reference(true)
            dbi::symbol_type::s_dataref_st: sym_reference(true)
            dbi::symbol_type::s_lprocref_st: sym_reference(true)
            dbi::symbol_type::s_procref: sym_reference(false)
            dbi::symbol_type::s_dataref: sym_reference(false)
            dbi::symbol_type::s_lprocref: sym_reference(false)
            dbi::symbol_type::s_gdata_hlsl: sym_data_hlsl
            dbi::symbol_type::s_ldata_hlsl: sym_data_hlsl
            dbi::symbol_type::s_gdata_hlsl32: sym_data_hlsl32
            dbi::symbol_type::s_ldata_hlsl32: sym_data_hlsl32
            dbi::symbol_type::s_gdata_hlsl32_ex: sym_data_hlsl32_ex
            dbi::symbol_type::s_ldata_hlsl32_ex: sym_data_hlsl32_ex
            _: sym_unknown
    instances:
      module_index:
        value: _parent.module_index
  dbi_extra_data:
    seq:
      - id: type
        type: u2
        enum: dbi::symbol_type
      # it looks like Microsoft forgot to update the length field for PROCREF_ST symbols
      # instead referring to this extra data as "hidden"
      - id: procref_data
        if: is_procref_st
        type: sym_reference(true)
    instances:
      is_procref_st:
        value: 'type == dbi::symbol_type::s_procref_st
          or type == dbi::symbol_type::s_lprocref_st'
      zzz_procref_alignment:
        if: is_procref_st
        type: align(procref_data.name.name_length + 1, 4)
      alignment:
        value: 'is_procref_st
          ? zzz_procref_alignment.value : 0'
      extra_length:
        value: 'is_procref_st
          ? zzz_procref_alignment.aligned
          : 0'
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
      - size: actual_length
    instances:
      zzz_extra_data:
        pos: data_pos
        type: dbi_extra_data
      data_pos:
        value: _io.pos
      actual_length:
        value: length + zzz_extra_data.extra_length 
      data:
        pos: data_pos
        size: actual_length
        type: dbi_symbol_data(actual_length)
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
      - id: lines
        size: _parent.lines_size
      - id: c13_lines
        size: _parent.c13_lines_size
        type: c13_lines
    instances:
      symbols_size:
        value: _parent.symbols_size - 4
  c13_subsection_ignore:
    seq:
      - id: data
        size-eos: true
  c13_column:
    doc-ref: 'CV_Column_t'
    seq:
      - id: column_start_offset
        type: u2
        doc-ref: 'offColumnStart'
      - id: column_end_offset
        type: u2
        doc-ref: 'offColumnEnd'
  c13_line:
    doc-ref: 'CV_Line_t'
    seq:
      - id: offset
        type: u4
        doc: 'Offset to start of code bytes for line number'
        doc-ref: 'offset'
      - id: linenum_start
        type: b24
        doc: 'line where statement/expression starts'
        doc-ref: 'linenumStart'
      - id: delta_line_end
        type: b7
        doc: 'delta to line where statement ends (optional)'
        doc-ref: 'deltaLineEnd'
      - id: is_statement
        type: b1
        doc: 'true if a statement linenumber, else an expression line num'
        doc-ref: 'fStatement'
    instances:
      is_special_not_step_onto:
        doc: 'The compiler will generate special line numbers like 0xfeefee (not to step onto)'
        value: linenum_start == 0xfeefee
      is_special_not_step_into:
        doc: 'The compiler will generate special line numbers like 0xf00f00 (not to step into)'
        value: linenum_start == 0xf00f00
  c13_file_block:
    seq:
      - id: file_id
        type: u4
      - id: num_lines
        type: u4
      - id: file_block_length
        type: u4
      - id: lines
        type: c13_line
        repeat: expr
        repeat-expr: num_lines
      - id: columns
        if: _parent.have_columns
        type: c13_column
        repeat: expr
        repeat-expr: num_lines
  c13_subsection_lines:
    seq:
      - id: contents_offset
        type: u4
      - id: contents_segment
        type: u2
      - id: flags
        type: u2
      - id: contents_size
        type: u4
      - id: file_blocks
        type: c13_file_block
        repeat: eos
    instances:
      have_columns:
        # CV_LINES_HAVE_COLUMNS: 0x1
        value: (flags & 0x1) == 0x1
  c13_subsection_stringtable:
    seq:
      - id: strings
        type: str
        terminator: 0
        encoding: UTF-8
        repeat: eos
  c13_frame_data:
    seq:
      - id: rva_start
        type: u4
      - id: block_size
        type: u4
      - id: locals_size
        type: u4
      - id: params_size
        type: u4
      - id: max_stack
        type: u4
      - id: frame_func
        type: u4
      - id: prolog_size
        type: u2
      - id: saved_regs_size
        type: u2
      - id: has_seh
        type: b1
      - id: has_eh
        type: b1
      - id: is_function_start
        type: b1
      - id: reserved
        type: b29
  c13_file_checksum:
    enums:
      checksum_type:
        0: none
        1: md5
        2: sha1
        3: sha256
    seq:
      - id: invoke_start_pos
        if: start_pos >= 0
        size: 0
      - id: filename_offset
        type: u4
      - id: checksum_size
        type: u1
      - id: checksum_type
        type: u1
        enum: checksum_type
      - id: checksum_data
        size: checksum_size
      - id: invoke_end_pos
        if: end_pos >= 0
        size: 0
      - id: alignment
        size: padding
    instances:
      start_pos:
        value: _io.pos
      end_pos:
        value: _io.pos
      zzz_alignment:
        type: align(end_pos - start_pos, 4)
      padding:
        value: zzz_alignment.aligned - zzz_alignment.value
  c13_inlinee_source_line:
    doc-ref: 'tagInlineeSourceLine'
    seq:
      - id: inlinee
        type: u4
        doc: 'function id.'
        doc-ref: 'inlinee'
      - id: file_id
        type: u4
        doc: 'offset into file table DEBUG_S_FILECHKSMS'
        doc-ref: 'fileId'
      - id: source_line_number
        type: u4
        doc: 'definition start line number.'
        doc-ref: 'sourceLineNum'
  c13_inlinee_source_line_ex:
    doc-ref: 'tagInlineeSourceLineEx'
    seq:
      - id: inlinee
        type: u4
        doc: 'function id.'
        doc-ref: 'inlinee'
      - id: file_id
        type: u4
        doc: 'offset into file table DEBUG_S_FILECHKSMS'
        doc-ref: 'fileId'
      - id: source_line_number
        type: u4
        doc: 'definition start line number.'
        doc-ref: 'sourceLineNum'
      - id: count_of_extra_files
        type: u4
        doc-ref: 'countOfExtraFiles'
      - id: extra_file_ids
        type: u4
        repeat: expr
        repeat-expr: count_of_extra_files
        doc-ref: 'extraFileId'
  c13_subsection_filechecksums:
    doc: 'file checksums'
    seq:
      - id: checksums
        type: c13_file_checksum
        repeat: eos
  c13_subsection_inlinee_lines:
    enums:
      signature:
        0: signature
        1: signature_ex
    seq:
      - id: signature
        type: u4
        enum: signature
      - id: lines
        if: signature == signature::signature
        type: c13_inlinee_source_line
        repeat: eos
      - id: lines_ex
        if: signature == signature::signature_ex
        type: c13_inlinee_source_line_ex
        repeat: eos
  c13_subsection_frame_data:
    seq:
      - id: frames
        type: c13_frame_data
        repeat: eos
  c13_subsection:
    seq:
      - id: type
        type: b31
        enum: c13_lines::subsection_type
        doc: 'DEBUG_S_SUBSECTION_TYPE'
      - id: is_ignored
        type: b1
        doc: 'if this bit is set in a subsection type then ignore the subsection contents'
        doc-ref: 'DEBUG_S_IGNORE'
      - id: length
        type: u4
      - size: length
        if: is_ignored
      - id: data
        if: is_ignored == false
        size: length
        type:
          switch-on: type
          cases:
            c13_lines::subsection_type::string_table: c13_subsection_stringtable
            c13_lines::subsection_type::il_lines: c13_subsection_lines
            c13_lines::subsection_type::lines: c13_subsection_lines
            c13_lines::subsection_type::ignore: c13_subsection_ignore
            c13_lines::subsection_type::file_chk_sms: c13_subsection_filechecksums
            c13_lines::subsection_type::inlinee_lines: c13_subsection_inlinee_lines
            c13_lines::subsection_type::frame_data: c13_subsection_frame_data
            _: c13_subsection_ignore
  c13_lines:
    enums:
      subsection_type:
        0x80000000: ignore # if this bit is set in a subsection type then ignore the subsection contents
        0xf1: symbols
        0xf2: lines
        0xf3: string_table
        0xf4: file_chk_sms
        0xf5: frame_data
        0xf6: inlinee_lines
        0xf7: cross_scope_imports
        0xf8: cross_scope_exports
        0xf9: il_lines
        0xfa: func_mdtoken_map
        0xfb: type_mdtoken_map
        0xfc: merged_assembly_input
        0xfd: coff_symbol_rva
    seq:
      - id: subsection
        type: c13_subsection
        repeat: eos
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
    doc: |
      OMFSegMap - This table contains the mapping between the logical segment indices
      used in the symbol table and the physical segments where the program is loaded
    doc-ref: 'OMFSegMapDesc'
    seq:
      - id: flags
        type: u2
        doc: 'descriptor flags bit field.'
        doc-ref: 'flags'
      - id: overlay_number
        type: u2
        doc: 'the logical overlay number'
        doc-ref: 'ovl'
      - id: group_index
        type: u2
        doc: 'group index into the descriptor array'
        doc-ref: 'group'
      - id: segment_index
        type: u2
        doc: 'logical segment index - interpreted via flags'
        doc-ref: 'frame'
      - id: segment_name_index
        type: u2
        doc: 'segment or group name - index into sstSegName'
        doc-ref: 'iSegName'
      - id: class_name_index
        type: u2
        doc: 'class name - index into sstSegName'
        doc-ref: 'iClassName'
      - id: offset
        type: u4
        doc: 'byte offset of the logical within the physical segment'
        doc-ref: 'offset'
      - id: size
        type: u4
        doc: 'byte count of the logical segment or group'
        doc-ref: 'cbSeg'
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
    doc: 'NMT'
    enums:
      version:
        1: hash
        2: hash_v2
    seq:
      - id: magic
        #contents: 0xeffeeffe
        contents: [0xfe, 0xef, 0xfe, 0xef]
        doc: 'verHdr'
      - id: version
        type: u4
        enum: version
        doc: 'vhT.ulHdr'
      - id: buffer
        type: pdb_buffer
        doc: 'buf'
      - id: indices
        type: pdb_array(4)
        doc: 'mphashni'
      - id: num_names
        type: u4
        doc: 'cni'
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
    doc-ref: 'FPO_DATA'
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
        doc-ref: 'ulOffStart'
      - id: proc_size
        type: u4
        doc: '# bytes in function'
        doc-ref: 'cbProcSize'
      - id: num_dwords_locals
        type: u4
        doc: '# bytes in locals/4'
        doc-ref: 'cdwLocals'
      - id: num_dwords_params
        type: u2
        doc: '# bytes in params/4'
        doc-ref: 'cdwParams'
      - id: prolog_size
        type: u1
        doc: '# bytes in prolog'
        doc-ref: 'cbProlog'
      - id: regs_size
        type: b3
        doc: '# regs saved'
        doc-ref: 'cbRegs'
      - id: has_seh
        type: b1
        doc: 'TRUE if SEH in func'
        doc-ref: 'fHasSEH'
      - id: use_bp
        type: b1
        doc: 'TRUE if EBP has been allocated'
        doc-ref: 'fUseBP'
      - id: reserved
        type: b1
        doc: 'reserved for future use'
        doc-ref: 'reserved'
      - id: frame_type
        type: b2
        enum: frame_type
        doc: 'frame type'
        doc-ref: 'cbFrame'
  fpo_stream:
    seq:
      - id: items
        repeat: eos
        type: fpo_data
  # contents of stream #1
  pdb_stream_hdr:
    doc-ref: 'PDBStream'
    seq:
      - id: implementation_version
        type: u4
        enum: pdb_implementation_version
        doc: 'implementation version number'
        doc-ref: 'impv'
      - id: sig
        type: u4
        doc: 'unique (across PDB instances) signature'
        doc-ref: 'sig'
      - id: age
        type: u4
        doc: 'no. of times this instance has been updated'
        doc-ref: 'age'
  guid:
    seq:
      - id: data1
        type: u4
      - id: data2
        type: u2
      - id: data3
        type: u2
      - id: data4
        type: u1
        repeat: expr
        repeat-expr: 8
  pdb_stream_hdr_vc70:
    seq:
      - id: sig70
        type: guid
  pdb_bitset_word:
    seq:
      - id: bits
        type: b1
        repeat: eos
  pdb_bitset:
    seq:
      - id: words
        type: pdb_array(4)
    instances:
      values:
        size: 0
        process: cat(words.data)
        type: pdb_bitset_word
  pdb_map_kv_pair:
    params:
      - id: index
        type: u4
    seq:
      - id: key
        if: is_present
        size: _parent.key_size
      - id: value
        if: is_present
        size: _parent.value_size
    instances:
      key_u4:
        if: is_present and _parent.key_size == sizeof<u4>
        pos: 0
        type: u4
      value_u4:
        if: is_present and _parent.value_size == sizeof<u4>
        pos: sizeof<u4>
        type: u4
      is_present:
        value: 
          _parent.available_bitset.values.bits[index]
  pdb_map:
    params:
      - id: key_size
        type: u4
      - id: value_size
        type: u4
    seq:
      - id: cardinality
        type: u4
      - id: num_elements
        type: u4
      - id: available_bitset
        type: pdb_bitset
      - id: deleted_bitset
        type: pdb_bitset
      - id: key_value_pairs
        type: pdb_map_kv_pair(_index)
        size: (key_size + value_size) * (available_bitset.values.bits[_index] ? 1 : 0)
        repeat: expr
        repeat-expr: num_elements
  string_slice:
    params:
      - id: offset
        type: u4
    seq:
      - size: offset
      - id: value
        type: str
        encoding: ascii
        terminator: 0
  pdb_named_stream:
    params:
      - id: index
        type: u4
    instances:
      item:
        value: _parent.map.key_value_pairs[index]
      name_offset:
        if: item.is_present
        value: item.key_u4
      stream_number:
        if: item.is_present
        value: item.value_u4
      name:
        if: item.is_present
        value: zzz_name.value
      zzz_name:
        if: item.is_present
        type: string_slice(name_offset)
        size: 0
        process: cat(_parent._parent.string_table_data.data)
      stream:
        if: item.is_present
        type: pdb_stream_ref_x(stream_number.as<s2>)
      name_map_stream:
        if: item.is_present and name == '/names'
        type: name_table
        size: 0
        process: cat(stream.data)
  pdb_map_named_streams:
    seq:
      - id: map
        type: pdb_map(sizeof<u4>, sizeof<u4>)
      - id: named_streams
        type: pdb_named_stream(_index)
        repeat: expr
        repeat-expr: map.num_elements
  name_table_ni:
    doc: 'NMTNI'
    seq:
      - id: string_table_data
        doc: 'pbuf'
        type: pdb_buffer
      - id: map_offset_index
        doc: 'mapSzoNi'
        #type: pdb_map(sizeof<u4>, sizeof<u4>)
        type: pdb_map_named_streams
      - id: max_index
        doc: 'niMac'
        type: u4
  u4_finder:
    params:
      - id: search
        type: u4
    seq:
      - id: buffer
        type: u4
        repeat: until
        repeat-until: _ == search or _io.eof
    instances:
      found: 
        value: buffer[end_pos - 4] == search
      start_pos:
        value: _io.pos
      end_pos:
        value: _io.pos
  pdb_stream:
    seq:
      - id: header
        type: pdb_stream_hdr
      - id: header_vc70
        if: is_vc70_pdb
        type: pdb_stream_hdr_vc70
      - id: name_table
        type: name_table_ni
      - id: invoke_extra_signatures_start
        size: 0
        if: extra_signatures_start >= 0
      - id: extra_signatures
        if: is_between_vc4_vc140
        type: u4
        repeat: expr
        repeat-expr: extra_signatures_count
    instances:
      zzz_find_vc110:
        pos: extra_signatures_start
        if: extra_signatures_count > 0
        size: extra_signatures_size
        type: u4_finder(pdb_implementation_version::vc110.to_i)
      zzz_find_vc140:
        pos: extra_signatures_start
        if: extra_signatures_count > 0
        size: extra_signatures_size
        type: u4_finder(pdb_implementation_version::vc140.to_i)
      zzz_find_no_type_merge:
        pos: extra_signatures_start
        if: extra_signatures_count > 0
        size: extra_signatures_size
        type: u4_finder(0x4D544F4E) # NOTM
      zzz_find_minimal_dbg_info:
        pos: extra_signatures_start
        if: extra_signatures_count > 0
        size: extra_signatures_size
        type: u4_finder(0x494E494D) # MINI
    
      zzz_extra_signatures_size:
        value: _io.size - extra_signatures_start
      extra_signatures_size:
        value: (zzz_extra_signatures_size / 4) * 4
      extra_signatures_count:
        value: 'is_between_vc4_vc140
          ? extra_signatures_size / 4
          : 0'
      extra_signatures_end:
        value: _io.pos
      extra_signatures_start:
        value: _io.pos
      is_between_vc4_vc140:
        value: 'header.implementation_version.to_i >= pdb_implementation_version::vc4.to_i
          and header.implementation_version.to_i <= pdb_implementation_version::vc140.to_i'
      is_vc2_pdb:
        value: stream_size == sizeof<pdb_stream_hdr>
      is_vc70_pdb:
        value: header.implementation_version.to_i > pdb_implementation_version::vc70_deprecated.to_i
      is_vc110_pdb:
        value: '(extra_signatures_count > 0) ? zzz_find_vc110.found : false'
      is_vc140_pdb:
        value: '(extra_signatures_count > 0) ? zzz_find_vc140.found : false'
      is_no_type_merge_pdb:
        value: '(extra_signatures_count > 0) ? zzz_find_no_type_merge.found : false'
      is_minimal_dbg_info_pdb:
        value: '(extra_signatures_count > 0) ? zzz_find_minimal_dbg_info.found : false'
      zzz_stream_size:
        type: get_stream_size(default_stream::pdb.to_i)
      stream_size:
        value: zzz_stream_size.value
      end_of_hdr:
        value: _io.pos
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
      symbols_data:
        value: 'is_new_hdr
          ? header_new.symbols_data
          : header_old.symbols_data'
      gs_symbols_data:
        value: 'is_new_hdr
          ? header_new.gs_symbols_data
          : header_old.gs_symbols_data'
      ps_symbols_data:
        value: 'is_new_hdr
          ? header_new.ps_symbols_data
          : header_old.ps_symbols_data'
      is_new_hdr:
        value: signature == -1
      # invalid gs/ps syms marker for DBI old/new detection
      signature:
        pos: 0
        type: s4
  pdb_header_jg:
    doc: 'page 0'
    doc-ref: 'MSF_HDR'
    seq:
      - size: 2
      - id: page_size
        type: u4
        doc: 'page size'
      - id: fpm_page_number
        type: u2
        doc: 'page no. of valid FPM'
      - id: num_pages
        type: u2
        doc: 'current no. of pages'
      - id: directory_size
        type: u4
        doc-ref: 'SI_PERSIST.cb'
      - id: page_map
        type: u4
        doc-ref: 'SI_PERSIST.mpspnpn'
  pdb_header_jg_old:
    doc: 'old C8.0 types-only program database header:'
    doc-ref: 'OHDR'
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
  zzz_pdb_data:
    type: get_stream_data(default_stream::pdb.to_i)
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
      : tpi.min_type_index'
  max_type_index:
    value: 'pdb_type == pdb_type::old
      ? pdb_jg_old.header.max_ti
      : tpi.max_type_index'
  types:
    value: 'pdb_type == pdb_type::old
      ? pdb_jg_old.types
      : tpi.types.types'
  pdb:
    size: 0
    type: pdb_stream
    process: cat(zzz_pdb_data.value)
  tpi:
    size: 0
    type: tpi
    process: cat(zzz_tpi_data.value)
  dbi:
    size: 0
    type: dbi
    if: zzz_dbi_data.has_data
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
  pdb_implementation_version:
    19941610: vc2
    19950623: vc4
    19950814: vc41
    19960307: vc50
    19970604: vc98
    20000404: vc70
    19990604: vc70_deprecated
    20030901: vc80
    20091201: vc110
    20140508: vc140
  