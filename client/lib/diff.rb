class Diff
	
	attr_reader :diff_out
	
	def Diff.lcs(a, b)
		astart = 0
		bstart = 0
		afinish = a.length-1
		bfinish = b.length-1
		mvector = []
		
		# First we prune off any common elements at the beginning
		while (astart <= afinish && bstart <= afinish && a[astart] == b[bstart])
			mvector[astart] = bstart
			astart += 1
			bstart += 1
		end
		    
		# now the end
		while (astart <= afinish && bstart <= bfinish && a[afinish] == b[bfinish])
			mvector[afinish] = bfinish
			afinish -= 1
			bfinish -= 1
		end
		
		bmatches = b.reverse_hash(bstart..bfinish)
		thresh = []
		links = []
		    
		(astart..afinish).each do |aindex|
			aelem = a[aindex]
			next unless bmatches.has_key? aelem
			k = nil
			bmatches[aelem].reverse.each do |bindex|
				if k && (thresh[k] > bindex) && (thresh[k-1] < bindex)
					thresh[k] = bindex
				else
					k = thresh.replacenextlarger(bindex, k)
				end
				links[k] = [ (k==0) ? nil : links[k-1], aindex, bindex ] if k
			end
		end
		
		if !thresh.empty?
			link = links[thresh.length-1]
			while link
				mvector[link[1]] = link[2]
				link = link[0]
			end
		end
		
		return mvector
	end
	
	def makediff(a, b)
		mvector = Diff.lcs(a, b)
		ai = bi = 0
		while ai < mvector.length
			bline = mvector[ai]
			if bline
				while bi < bline
					discardb(bi, b[bi])
					bi += 1
				end
				match(ai, bi)
				bi += 1
			else
				discarda(ai, a[ai])
			end
			ai += 1
		end
		while ai < a.length
			discarda(ai, a[ai])
			ai += 1
		end
		while bi < b.length
			discardb(bi, b[bi])
			bi += 1
		end
		match(ai, bi)
		1
	end
	
	def compactdiffs
		diffs = []
		@diffs.each do |df|
			i = 0
			curdiff = []
			while i < df.length
				whot = df[i][0]
				s = @isstring ? df[i][2].chr : [df[i][2]]
				p = df[i][1]
				last = df[i][1]
				i += 1
				while df[i] && df[i][0] == whot && df[i][1] == last+1
					s << df[i][2]
					last  = df[i][1]
					i += 1
				end
				curdiff.push [whot, p, s]
			end
			diffs.push curdiff
		end
		return diffs
	end
	
	attr_reader :diffs, :difftype
	
	def initialize(diffs_or_a, b = nil, isstring = nil)
		if b.nil?
			@diffs = diffs_or_a
			@isstring = isstring
		else
			@diffs = []
			@curdiffs = []
			makediff(diffs_or_a, b)
			@difftype = diffs_or_a.class
		end
	end
	  
	def match(ai, bi)
		@diffs.push @curdiffs unless @curdiffs.empty?
		@curdiffs = []
	end
	
	def discarda(i, elem)
		@curdiffs.push ['-', i, elem]
	end
	
	def discardb(i, elem)
		@curdiffs.push ['+', i, elem]
	end
	
	def compact
		return Diff.new(compactdiffs)
	end
	
	def compact!
		@diffs = compactdiffs
	end
	
	def inspect
		@diffs.inspect
	end
	
	def diffrange(a, b)
		if (a == b)
			"#{a}"
		else
			"#{a},#{b}"
		end
	end
	
	def to_diff(io = $defout)
		@diff_out = ""
		offset = 0
		@diffs.each do |b|
			first = b[0][1]
			length = b.length
			action = b[0][0]
			addcount = 0
			remcount = 0
			b.each do |l| 
				if l[0] == "+"
					addcount += 1
				elsif l[0] == "-"
					remcount += 1
				end
			end
			if addcount == 0
				note = "#{diffrange(first+1, first+remcount)}d#{first+offset}"
			elsif remcount == 0
				note = "#{first-offset}a#{diffrange(first+1, first+addcount)}"
			else
				note = "#{diffrange(first+1, first+remcount)}c#{diffrange(first+offset+1, first+offset+addcount)}"
			end
			@diff_out += "--#{note}--\n"
			lastdel = (b[0][0] == "-")
			b.each do |l|
				if l[0] == "-"
					offset -= 1
					@diff_out += "Sent from this host :  "
				elsif l[0] == "+"
					offset += 1
					if lastdel
						lastdel = false
					end
					@diff_out += "Received by server  :  "
				end
				@diff_out += l[2]
			end
		end
	end
  
end  # class Diff


module Diffable
	
	def diff(b)
		Diff.new(self, b)
	end
	
	# Create a hash that maps elements of the array to arrays of indices
	# where the elements are found.
	
	def reverse_hash(range = (0...self.length))
		revmap = {}
		range.each do |i|
			elem = self[i]
			if revmap.has_key? elem
				revmap[elem].push i
			else
				revmap[elem] = [i]
			end
		end
		return revmap
	  end

	  def replacenextlarger(value, high = nil)
		high ||= self.length
		if self.empty? || value > self[-1]
			push value
			return high
		end
		# binary search for replacement point
		low = 0
		while low < high
			index = (high+low)/2
			found = self[index]
			return nil if value == found
			if value > found
				low = index + 1
			else
				high = index
			end
		end
		
		self[low] = value
		return low
	end
	
	def patch(diff)
		newary = nil
		if diff.difftype == String
			newary = diff.difftype.new('')
		else
			 newary = diff.difftype.new
		end
		ai = 0
		bi = 0
		diff.diffs.each do |d|
			d.each do |mod|
				case mod[0]
				when '-'
					while ai < mod[1]
						newary << self[ai]
						ai += 1
						bi += 1
					end
					ai += 1
				when '+'
					while bi < mod[1]
						newary << self[ai]
						ai += 1
						bi += 1
					end
					newary << mod[2]
					bi += 1
				else
					raise "Unknown diff action"
				end
			end
		end
		while ai < self.length
			newary << self[ai]
			ai += 1
			bi += 1
		end
		return newary
	end
	  
end  # module Diffable


class Array
	include Diffable
end


class String
	include Diffable
end
