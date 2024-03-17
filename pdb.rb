class Concat
	attr_reader :blocks

	def initialize(items)
		@blocks = items.map(&:data)
	end

	def decode(src)
		return @blocks.join('')
	end
end

class ConcatPages
	attr_reader :blocks

	def initialize(items)
		@blocks = items.map(&:page)
	end

	def decode(src)
		return Concat.new(@blocks).decode(src)
	end
end

class Cat
	attr_reader :item

	def initialize(item)
		@item = item
	end

	def decode(src)
		return @item
	end
end
 