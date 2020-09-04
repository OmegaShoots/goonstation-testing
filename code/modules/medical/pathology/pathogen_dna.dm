/**
 * Pathogen DNA
 *
 * The pathogen DNA sequence consists of two separately handled parts:
 * - The "private" sequence is basically a sequence that contains
 *   - the unique identifier of the microbody of the pathogen, which must be defined in the /datum/microbody subclass.
 *     the pathogen controller contains a lookup table of the existing microbody IDs for fast lookup, reducing search times from O(n) to O(1).
 *   - the numeric values of the pathogen, sequentially, as two byte signed integers, which means each numeric value is encoded in the DNA sequence as four hexadecimal digits
 *   - a single digit signifying the amount of stages of a pathogen
 *   - a single digit signifying if the pathogen is symptomatic
 *     at the time of writing this documentation, the sequence of the numeric values is:
 *     mutativeness | mutation speed | advance speed | maliciousness | suppression threshold | stages
 *   EXAMPLE: A pathogen that is a virus, with a mutativeness of 19, a mutation speed of 6, an advance speed of 5, a maliciousness of 7
 *            and a suppression threshold of 5, 5 stages and symptomatic carries the following DNA sequence:
 *            00010013000600050007000551
 *   DEVELOPER NOTE: The encoding is NOT two's complement as any coder would expect, due to the fact that I have no idea how
 *   BYOND numbers are represented. The encoding of the two bytes is 2 byte one's complement. (I think. Whatever.)
 *   NOTE: While any of these values are highly unlikely to ever pass 255, I'll leave it open for two bytes.
 *   This private sequence is only ever printed and cannot be directly spliced. Modifying the numeric values is done through seed mutation logic.
 *   Since this part of the DNA is never directly modified, this part is always calculated from the numeric values.
 * - The "public" sequence is the sequence that contains
 *   - The suppressant of the pathogen. Each suppressant is given a round-randomized 3 quartet (1.5 byte) unique identifier by the pathogen controller upon round setup.
 *     A lookup table of available suppressants is available in the pathogen controller for fast processing.
 *   - A single separator to signal the end of suppressants and the beginning of carriers.
 *	 - All carriers, sequentially. Carriers are assigned 3 quartets as well, and they have their own lookup table.
 *   - Anything I may have forgot to mention is also here.
 *   - A single separator to signal the beginning of the symptoms.
 *   - All symptoms of the pathogen sequentially. This might and will cause the DNA to inflate to a very large and complex sequence if a very mutative pathogen is introduced to the station.
 *     A symptom is composed of R * 3 quartets, where R represents rarity, followed by a 'DNA separator' marked by a | in the DNA.
 *     Rarity is a value from 1 to 5, where 1 is VERY COMMON and 5 is VERY RARE. All symptoms are assigned this value as their unique identifier and an unique identifier is generated for
 *     each symptom at round setup following this pattern:
 *     1) All VERY_COMMON symptoms are assigned a symptom-unique round randomized 3 quartet (eg. 1F3 is now sweating and EE2 is now farting)
 *     2) All symptoms of rarity R (where R is the next lowest rarity category not yet processed) are assigned a 3R quartet. First, a set of available identifiers is generated by taking
 *        each identifier for rarity R-1 symptoms, and prepending and appending the identifier of all VERY_COMMON symptoms. This will generate a moderate amount of collisions (for example
 *        prepeding 1F3 to EE20AB yields the same as appending 0AB to 1F3EE2), which are then eliminated. Then, rarity R symptoms are each assigned a randomly pick()-ed identifier from this
 *        list. If, due to an inbalance in the amount of symptoms available there is no ID that is left avaiable and the sequence will be a randomly generated 3R quartet. This, of course,
 *        means that the symptom cannot be synthesized via pathology science that round. Tough luck.
 *        At the time of writing this documentation, the numbers add up and all symptoms should be synthesizable. At current time, it is also hard to synthesize a VERY_RARE symptom. which
 *        is intended and a good thing.
 *     The DNA separators are a sort of 'resource' available to pathologists, although infinite of them is produceable through replicating DNA. If someone can come up with any reasonable way
 *     to limit DNA separators, I am open to implementing it.
 *     What is a DNA separator though? Well, as the above algorithm shows, the identifier sequence of each high tier symptom is composed of VALID sequences for lower tier symptoms. To be able
 *     to determine which symptom is supposed to be a higher tier one, symptoms must be separated by a ~magical nucleic acid~ we call the DNA separator. This means that a pathogen of K symptoms
 *     will contain K-1 DNA separators.
 *     The pathogen controller will contain a symptom lookup table and an inverse table for looking up the numeric identifier.
 *     Due to the nature of this, we are limited to 4096 (2^12, 3 quartets) VERY_COMMON symptoms. Oh the horror.
 *   This part of the DNA is modifiable through splicing. During a splicing session, you can scrap parts of the DNA and introduce new parts from already existing DNA. Once the splicing session
 *   is complete, the DNA is evaluated (compiled) and destroyed if it contains an invalid sequence (such as an attempt to create a tier three symptom, but no tier three symptom having that
 *   specific DNA sequence). I believe pathologists will be kept busy by making their ~fancy symptoms~ all round, and it's not as straightforward as chemistry or as boring as genetics.
 *   EXAMPLE: Suppose that sweating is 1F3, farting is EE2, coughing is sweating + farting (1F3EE2) and the heat weakness suppressant is 0C3.
 *   The DNA sequence for a pathogen with the above three symptoms, no carriers and heat weakness would be:
 *   0C3||1F3|EE2|1F3EE2
 *   During splicing, moving could only be done by moving coherent parts. A coherent part is a 3 quartet beginning at a 3 quartet boundary or after a DNA separator. This means one could move
 *   1F3 or EE2 out of 1F3EE2 but not 3EE or F3E. A single DNA separator is also a coherent part. A coherent part could only be moved to a boundary (ie. inserted between two existing coherent
 *   parts)
 *   EXAMPLE: Suppose that no symptom gained the unique identifier of farting + sweating (EE21F3). A pathologist splicing the above DNA sequence into
 *   0C3||1F3|EE21F3
 *   would be in for a nasty surprise, as the DNA collapses, due to EE21F3 being an invalid sequence.
 *   Due to the nature of the rolling unique identifiers, of course it does not mean EE21F3AB0 couldn't be a valid sequence, as a symptom with the sequence 1F3AB0 could exist, and a higher
 *   tier symptom could have EE2 prepended to this. This means that only ELEMENTARY (3 quartet starting at boundary) subsets of a symptom's unique identifier is also guaranteed to be a
 *   valid unique identifier.
 */

/**
 * Pathogen mutate-and-effect graph
 *
 * When numeric values of pathogens are mutated, other values are mutated in the other direction. This graph defines the mutation of which values effect which other values.
 * (For every action, there is an equal and opposite reaction, except it's not equal because that would be annoying and I'm not trying to apply Newton's third law of motion)
 *
 * mutativeness ------------- advance_speed
 *     |                    /
 *     |        maliciousness
 *     |                    \
 * sthreshold --------------- mutation_speed
 *
 * ...sometimes I wish BYOND had pointers because it would be so much cleaner. I'm not going to use whatever twisted thing DM called refs.
 */

datum/pathogendna
	var/seqnumeric = "00000000000000000000000000"
	var/seqsplice = ""

	var/valid = 0

	var/datum/pathogen/reference = null

	New(var/datum/pathogen/P)
		..()
		if (P)
			reference = unpool(/datum/pathogen)
			reference.setup(0, P, 0, src)
			recalculate()
			reverse_engineer()
			valid = 1
		else
			reference = unpool(/datum/pathogen)
			valid = 0

	proc/clone()
		var/datum/pathogendna/D = new(reference)
		return D

	proc/manipulate(value, direction)
		var/datum/pathogendna/this = src
		src = null
		//I think the chance to mutate serves as a perfectly fine deterrent to overengineering your pathogen's DNA
		/*
		if (prob(2))
			del this
			return 0
		*/
		if (prob(4))
			this.reference.mutate()
			this.recalculate()
			this.reverse_engineer()
			return -1
		if (direction > 0)
			direction = 1
		else
			direction = -1
		if (!this)
			return 0 // We somehow lost the DNA.
		switch (value)
			if ("mutativeness")
				this.reference.mutativeness += rand(1, 3) * direction
				this.reference.advance_speed -= rand(0, 1) * direction
				this.reference.suppression_threshold -= rand(0, 1) * direction
			if ("suppression_threshold")
				this.reference.suppression_threshold += rand(1, 3) * direction
				this.reference.mutation_speed -= rand(0, 1) * direction
				this.reference.mutativeness -= rand(0, 1) * direction
			if ("mutation_speed")
				this.reference.mutation_speed += rand(1, 3) * direction
				this.reference.suppression_threshold -= rand(0, 1) * direction
				this.reference.maliciousness -= rand(0, 1) * direction
			if ("maliciousness")
				this.reference.maliciousness += rand(1, 3) * direction
				this.reference.advance_speed -= rand(0, 1) * direction
				this.reference.mutation_speed -= rand(0, 1) * direction
			if ("advance_speed")
				this.reference.advance_speed += rand(1, 3) * direction
				this.reference.mutativeness -= rand(0, 1) * direction
				this.reference.maliciousness -= rand(0, 1) * direction
		if (this.reference.mutation_speed < 0)
			this.reference.mutation_speed = 0
		this.recalculate()
		return 1

	proc/explode()
		var/list/ret = new/list()
		var/pos = 1
		while (pos < length(seqsplice))
			if (copytext(seqsplice, pos, pos + 1) != "|")
				ret += copytext(seqsplice, pos, pos + 3)
				pos += 3
			else
				ret += "|"
				pos += 1
		return ret

	proc/implode(var/list/parts)
		var/newseq = ""
		for (var/i = 1, i <= parts.len, i++)
			newseq += parts[i]
		seqsplice = newseq
		valid = 0
		return

	proc/get_sequences()
		var/list/seq = list()
		var/list/parts = explode()
		var/i = 1
		var/s = 0
		while (i < parts.len && s < 2)
			if (parts[i] == "|")
				s++
			i++
		if (s < 2)
			return seq
		var/act_seq = ""
		while (i < parts.len)
			if (parts[i] == "|")
				if (act_seq != "")
					seq += act_seq
				else
					return list() // error
				act_seq = ""
			else
				act_seq += parts[i]
			i++
		if (act_seq == "")
			return list()
		seq += act_seq
		return seq

	// Pathogen numeric -> DNA/Private
	proc/recalculate()
		// BYOND number vars are unreliable. All numbers are rounded.
		var/uid = num2hexoc(round(src.reference.body_type.uniqueid), 4)
		var/mut = num2hexoc(round(src.reference.mutativeness), 4)
		var/mts = num2hexoc(round(src.reference.mutation_speed), 4)
		var/adv = num2hexoc(round(src.reference.advance_speed), 4)
		var/mal = num2hexoc(round(src.reference.maliciousness), 4)
		var/sup = num2hexoc(round(src.reference.suppression_threshold), 4)
		src.seqnumeric = "[uid][mut][mts][adv][mal][sup][src.reference.stages][src.reference.symptomatic]"

	// DNA/Private -> Pathogen numeric
	proc/reevaluate_numeric()
		var/uid = hex2numoc(copytext(seqnumeric, 1, 5))
		var/mut = hex2numoc(copytext(seqnumeric, 5, 9))
		var/mts = hex2numoc(copytext(seqnumeric, 9, 13))
		var/adv = hex2numoc(copytext(seqnumeric, 13, 17))
		var/mal = hex2numoc(copytext(seqnumeric, 17, 21))
		var/sup = hex2numoc(copytext(seqnumeric, 21, 25))
		var/stages = text2num(copytext(seqnumeric, 25, 26))
		var/symptomatic = text2num(copytext(seqnumeric, 26, 27))
		src.reference.mutativeness = mut
		src.reference.mutation_speed = mts
		src.reference.advance_speed = adv
		src.reference.maliciousness = mal
		src.reference.suppression_threshold = sup
		src.reference.stages = stages
		src.reference.symptomatic = symptomatic
		for(var/T in pathogen_controller.path_to_microbody)
			var/datum/microbody/B = pathogen_controller.path_to_microbody[T]
			if (B.uniqueid == uid)
				src.reference.body_type = B
				src.reference.stages = B.stages
				break

	// Pathogen data -> DNA/Public
	proc/reverse_engineer()
		src.seqsplice = pathogen_controller.suppressant_to_UID[reference.suppressant.type]
		src.seqsplice += "|"
		//for (var/datum/pathogen_carrier/C in src.reference.carriers)
		//	src.seqsplice += pathogen_controller.carrier_to_UID[C.type]
		src.seqsplice += "|"
		var/first = 1
		for (var/datum/pathogeneffects/E in src.reference.effects)
			if (!first)
				src.seqsplice += "|"
			else
				first = 0
			src.seqsplice += pathogen_controller.symptom_to_UID[E.type]

	// DNA/Public -> Pathogen data
	proc/reevaluate()
		// Move src reference so we can return false if evaluation fails (important for whatever is calling this)
		var/datum/pathogendna/this = src
		src = null
		var/desc = this.reference.desc
		var/name_base = this.reference.name_base
		var/mutation = this.reference.mutation
		var/uid = this.reference.pathogen_uid
		this.reference.clear()
		this.reference.desc = desc
		this.reference.name_base = name_base
		this.reference.base_mutation = mutation
		this.reference.pathogen_uid = uid
		this.reference.mutation = pathogen_controller.next_mutation[num2text(uid)]
		this.reference.stage = 1
		this.reference.name = "[name_base][mutation]"
		pathogen_controller.next_mutation[num2text(uid)] += 1
		this.reevaluate_numeric()
		// Partition the DNA for traversal.
		var/list/parts = this.explode()
		if (!(parts[1] in pathogen_controller.UID_to_suppressant))
			//log_game("[this.seqsplice] collapses: non-existent suppressant.")
			qdel(this) // Bad DNA: Invalid suppressant.
			return 2
		else
			if (this)
				var/supp = pathogen_controller.UID_to_suppressant[parts[1]]
				this.reference.suppressant = pathogen_controller.path_to_suppressant[supp]
			else
				return 0 // Somehow, we lost the DNA.
		if (parts[2] != "|")
			//log_game("[this.seqsplice] collapses: no separator after suppressant.")
			qdel(this)
			return 3 // Bad DNA: no separator after suppressant.
		var/pos = 2
		if (parts[3] == "|")
			pos = 4 // No carriers.
		else
			pos = 3
			while (pos <= parts.len && parts[pos] != "|")
				if (!(parts[pos] in pathogen_controller.UID_to_carrier))
					//log_game("[this.seqsplice] collapses: non-existent carrier.")
					qdel(this) // Bad DNA: Invalid carrier
					return 4
				else
					if (this)
						this.reference.carriers += pathogen_controller.UID_to_carrier[parts[pos]]
					else
						return 0 // Somehow, we lost the DNA.
				pos++
			if (pos == parts.len)
				//log_game("[this.seqsplice] collapses: no separator after carriers.")
				qdel(this) // Bad DNA: No ending separator after carriers.
				return 5
			pos++

		// Assemble the list of symptoms.
		var/symptom = ""

		while (pos <= parts.len)
			if (parts[pos] == "|")
				if (symptom != "")
					// Validate symptom
					if (!(symptom in pathogen_controller.UID_to_symptom))
						//log_game("[this.seqsplice] collapses: non-existent symptom [symptom].")
						qdel(this) // Bad DNA: DNA contains invalid symptom
						return 6
					else
						if (this)
							var/sym = pathogen_controller.UID_to_symptom[symptom]
							this.reference.effects += pathogen_controller.path_to_symptom[sym]
							symptom = ""
						else
							return 0 // Somehow, we lost the DNA.
				else
					//log_game("[this.seqsplice] collapses: two adjacent symptom separators.")
					qdel(this) // Bad DNA: DNA contains two adjacent separators
					return 7
			else
				symptom += parts[pos]
			pos++
		if (symptom != "")
			if (!(symptom in pathogen_controller.UID_to_symptom))
				//log_game("[this.seqsplice] collapses: non-existent symptom [symptom].")
				qdel(this) // Bad DNA: DNA contains invalid symptom
				return 6
			else
				if (this)
					var/sym = pathogen_controller.UID_to_symptom[symptom]
					this.reference.effects += pathogen_controller.path_to_symptom[sym]
				else
					return 0 // Somehow, we lost the DNA.

		var/effectSeqSum = 0
		for (var/effect in this.reference.effects)
			if(istype(effect, /datum/pathogeneffects))
				var/datum/pathogeneffects/E = effect
				effectSeqSum += E.rarity
		if(effectSeqSum > this.reference.body_type.seqMax && this.reference.body_type.seqMax != -1)
			return 8 // too many symptoms for microbody type


		// DNA has been completely evaluated if we reach this point in execution and it is a valid pathogen DNA. Hooray!
		// Build the available symptom list for the pathogen.
		this.reference.dnasample = this
		this.valid = 1
		return 1 // Success.

	proc/regenerate_uid()
		src.reference.pathogen_uid = "[pathogen_controller.next_uid]"
		src.reference.mutation = pick(pathogen_controller.lnums)
		src.reference.name_base = pick(pathogen_controller.lalph) + pick(pathogen_controller.lnums) + pick(pathogen_controller.lalph)
		src.reference.name = src.reference.name_base + "[src.reference.mutation]"
		pathogen_controller.next_uid++

	proc/move_mutation()
		src.reference.mutation = pathogen_controller.next_mutation[src.reference.pathogen_uid]
		pathogen_controller.next_mutation[src.reference.pathogen_uid] += 1
		src.reference.name = src.reference.name_base + "[src.reference.mutation]"
