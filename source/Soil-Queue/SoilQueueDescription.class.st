"
The persisted half of a queue: where its entries live, how they are ordered, and
everything else that has to outlive the image.

I am not the queue. The queue coordinates between workers and therefore has to be one
object in memory, which a database object cannot be -- two transactions materialize two
of me. So the durable part is mine and the live part is the queue's, the same cut the
resident system makes everywhere.

What I hold: the strategy, which decides which index the entries lie on and which
section of it, and the format, which decides how they are ordered. Both are read
whenever I am read and nowhere else, so neither is a cluster root of its own.

The index is. I make it one in #initializeFrom:, which is where a description creates
the objects its resident works on. That also spares the queue a trap: Soil sends
#soilClusterRootIn: only out of #makeRoot:, never to an object it promotes on its own
because the class says #isSoilClusterRoot -- so an index that only ever arrived by
reference would be stored with no transaction at all.

My name is an instance variable rather than a constant of my class, which is where the
resident system usually puts it. A queue is created at runtime and there can be many,
and the registry keys by name.
"
Class {
	#name : #SoilQueueDescription,
	#superclass : #SoilResidentDescription,
	#instVars : [
		'name',
		'strategy',
		'format',
		'deadLetters',
		'workerLimit',
		'orphanedRetryLimit',
		'failureRetryLimit',
		'backoffBase',
		'backoffCap',
		'rateLimit',
		'ratePeriod'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueDescription class >> named: aSymbol strategy: aStrategy format: aFormat [

	^ self new
		setName: aSymbol
		strategy: aStrategy
		format: aFormat
]

{ #category : #'instance creation' }
SoilQueueDescription class >> named: aSymbol timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes [
	"the ordinary queue: an index of its own, ordered by due time"

	^ self
		named: aSymbol
		strategy: (SoilQueueStrategy ownIndexWithBackend: anIndexClass keySize: keySizeInBytes)
		format: SoilQueueTimeOrderedKeyFormat new
]

{ #category : #adding }
SoilQueueDescription >> add: anEntry [
	"put an entry in, in the transaction I was read in -- I do not commit. The
	notification that wakes a worker belongs after that commit, not here: before it there
	is nothing to find.

	Answers the key in the form the index compares in, which is the form everything else
	hands around too. #keyFor: answers the other form, the bytes it is composed of."

	| key |
	key := self keyFor: anEntry.
	strategy index at: key put: anEntry.
	^ key asIndexKeyOfSize: strategy range keySize
]

{ #category : #converting }
SoilQueueDescription >> appendKeyPartsFor: anEntry on: aWriteStream [
	"the embedder's link in the chain, and the place a section inside one queue is marked.
	Nothing by default -- whoever has nothing to contribute contributes nothing"
]

{ #category : #retrying }
SoilQueueDescription >> backoffBase [
	"the pause before the first retry. Every further failure doubles it, up to
	#backoffCap. One second by default, so that a short disturbance -- a dropped
	connection -- is over quickly"

	^ backoffBase ifNil: [ 1 second ]
]

{ #category : #retrying }
SoilQueueDescription >> backoffBase: aDuration [

	backoffBase := aDuration
]

{ #category : #retrying }
SoilQueueDescription >> backoffCap [
	"the longest pause between two retries, however often the work has failed. An hour by
	default"

	^ backoffCap ifNil: [ 1 hour ]
]

{ #category : #retrying }
SoilQueueDescription >> backoffCap: aDuration [

	backoffCap := aDuration
]

{ #category : #accessing }
SoilQueueDescription >> deadLetter: aKey [
	"park an entry that could not be worked on at all, and take it out of the ordering.

	Put first and removed second, so that an abort in between leaves it where it was rather
	than nowhere. It keeps its key: it is the same entry, only somewhere else."

	| entry |
	entry := self entryAt: aKey.
	entry markDeadLetter.
	deadLetters at: aKey put: entry.
	self removeKey: aKey.
	^ entry
]

{ #category : #enumerating }
SoilQueueDescription >> deadLettersDo: aBlock [
	"the parked entries with their keys. Nobody is woken for these -- they are here to be
	looked at"

	deadLetters newIterator associationsDo: [ :each |
		aBlock value: each key value: each value ]
]

{ #category : #accessing }
SoilQueueDescription >> dueCountAt: aDateAndTime upTo: aLimit [
	"how many entries are due, counted no further than aLimit.

	The number is only ever used to decide how many workers to have, so counting past the
	limit would buy nothing. The walk stops at the first entry that is not due either,
	because the ordering is by due time and nothing behind it can be due.

	Only pending entries count. One that says claimed is with a worker already, or waiting
	for the recovery pass, and in neither case does it call for another worker."

	| count |
	count := 0.
	self keysAndEntriesDo: [ :key :entry |
		entry eligibleAt > aDateAndTime ifTrue: [ ^ count ].
		entry isPending ifTrue: [
			count := count + 1.
			count >= aLimit ifTrue: [ ^ count ] ] ].
	^ count
]

{ #category : #accessing }
SoilQueueDescription >> entryAt: aKey [

	^ strategy index at: aKey
]

{ #category : #accessing }
SoilQueueDescription >> entryAt: aKey ifAbsent: aBlock [

	^ strategy index at: aKey ifAbsent: aBlock
]

{ #category : #retrying }
SoilQueueDescription >> failureRetryLimit [
	"how often a work unit that failed retriably is tried again before the entry gives up.
	Three by default. A retry is only ever asked for by an entry that calls an error
	retriable, and what it costs -- a far side hit again, a quota used up -- is why the
	budget is narrow"

	^ failureRetryLimit ifNil: [ 3 ]
]

{ #category : #retrying }
SoilQueueDescription >> failureRetryLimit: anInteger [

	anInteger < 0 ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	failureRetryLimit := anInteger
]

{ #category : #accessing }
SoilQueueDescription >> format [

	^ format
]

{ #category : #initialization }
SoilQueueDescription >> initializeFrom: aTransaction [
	"the index is a cluster root of its own. Two things follow, and both are wanted: it is
	not copied into my cluster, and two queues that share one index share one object
	instead of each getting a copy that overwrites the other's.

	The dead letters get a second index, never shared. Out of the ordering, so that a
	parked entry is not stepped over on every scan for work, and still in the store, so
	that it can be found and looked at -- work that disappears without a trace is worse
	than work that sits there unfinished."

	strategy makeIndexRootIn: aTransaction.
	deadLetters := (SoilIndexedDictionary newWithBackend: strategy backend)
		keySize: strategy range keySize;
		maxLevel: 16;
		yourself.
	aTransaction makeRoot: deadLetters
]

{ #category : #'instance creation' }
SoilQueueDescription >> instanceClass [

	^ SoilQueue
]

{ #category : #converting }
SoilQueueDescription >> keyFor: anEntry [
	"the chain: the format orders, an embedder may add its own part, and the strategy
	places the result inside its section -- marker first, padding last, filling the whole
	key size.

	No single participant knows the whole key. The entry supplies values and never a key,
	so that two entries of one queue cannot sort by different rules."

	^ strategy keyWith: (ByteArray streamContents: [ :parts |
		format appendKeyPartsFor: anEntry on: parts.
		self appendKeyPartsFor: anEntry on: parts ])
]

{ #category : #enumerating }
SoilQueueDescription >> keysAndEntriesDo: aBlock [
	"every entry of my section with its key, in key order.

	The only reader of this is the recovery pass, and it reads every entry because that is
	where the answer is: an orphaned claim cannot be found over the index, since a claim
	does not change the key. Selecting work does not come this way -- it reads one entry
	and stops."

	| iterator scanKey found |
	iterator := strategy newIterator.
	scanKey := strategy range firstIndexKey.
	[ found := iterator nextKeyCloseTo: scanKey.
	  found notNil and: [ strategy range includesKey: found ] ] whileTrue: [
		aBlock value: found value: (iterator at: found).
		scanKey := found + 1 ]
]

{ #category : #moving }
SoilQueueDescription >> moveKey: aKey for: anEntry [
	"put anEntry under the key it asks for now, and answer that key. Its due time may have
	changed since it came in -- that is how a follow-up later and a backoff are expressed --
	and the key is what sorts by it. Unchanged, nothing is written.

	One move rather than a removal and an insertion, because the removal answers an
	unloaded proxy and an insertion would resolve it: the target would be read from disk
	only to change the number it is filed under. Asked of the index and not of an iterator
	on it -- the index is the one that writes the journal and marks itself for the commit."

	| newKey |
	newKey := (self keyFor: anEntry) asIndexKeyOfSize: strategy range keySize.
	newKey = aKey ifTrue: [ ^ aKey ].
	strategy index moveKey: aKey to: newKey.
	^ newKey
]

{ #category : #accessing }
SoilQueueDescription >> name [

	^ name
]

{ #category : #'instance creation' }
SoilQueueDescription >> newInstanceIn: aTransaction [
	"the name goes along, so the live queue can answer for itself what it is called
	without opening a transaction for a label. So do the settings, as they stand now:
	a queue that is created and never started still runs by them, and a start reads
	them again"

	^ (super newInstanceIn: aTransaction)
		name: name;
		settings: self settings;
		yourself
]

{ #category : #accessing }
SoilQueueDescription >> nextDueAt: aDateAndTime skipping: aCollection ifNone: aBlock [
	"the key of the oldest entry that is due, skipping the keys that are already out.

	When nothing is due, aBlock is evaluated with the time the next entry becomes due, or
	with nil when there is nothing at all -- so a caller can sleep exactly as long as it
	has to rather than come back and ask again.

	The scan jumps rather than steps: to the start of my section, then past each key it
	looked at. What ends it is the range, which says where the section stops, because the
	index has no idea that it is shared. Past the last key of the index the positioning
	call answers nil, so that end takes care of itself.

	Only pending entries are handed out. An entry that says claimed belongs to a worker, or
	to the recovery pass if no worker holds it -- and it stays in the ordering either way,
	because a claim does not change a key. Without this a work unit that throws would be
	handed straight back to the next worker, for ever."

	| iterator range scanKey found |
	range := strategy range.
	iterator := strategy newIterator.
	scanKey := range firstIndexKey.
	[ found := iterator nextKeyCloseTo: scanKey.
	  found notNil and: [ range includesKey: found ] ]
		whileTrue: [
			(aCollection includes: found)
				ifTrue: [ scanKey := found + 1 ]
				ifFalse: [
					| entry |
					entry := iterator at: found.
					entry isPending
						ifFalse: [ scanKey := found + 1 ]
						ifTrue: [
							entry eligibleAt <= aDateAndTime ifTrue: [ ^ found ].
							^ aBlock cull: entry eligibleAt ] ] ].
	^ aBlock cull: nil
]

{ #category : #accessing }
SoilQueueDescription >> nextDueTimeAt: aDateAndTime [
	"when the first entry of my section may run: aDateAndTime itself when one is already
	due, the time of the earliest one when none is, and nil when the section holds nothing.

	One of the two questions an embedder asks a queue. It answers a time rather than a key
	because the asker is not going to work on it -- it wants to know how long it may sleep,
	or whether the database is quiet enough to close."

	self
		nextDueAt: aDateAndTime
		skipping: #(  )
		ifNone: [ :time | ^ time ].
	^ aDateAndTime
]

{ #category : #accessing }
SoilQueueDescription >> orphanedRetryLimit [
	"how often an entry may lose its worker and be given back before it is parked as a dead
	letter. nil means no limit, and nil is the default: an entry that takes its worker
	with it every time -- the poison entry -- is the case the limit is for, and how many
	lost workers are too many depends on what the work does and how often the embedder
	deploys. That is the embedder's knowledge; a number here would be a guess"

	^ orphanedRetryLimit
]

{ #category : #accessing }
SoilQueueDescription >> orphanedRetryLimit: anInteger [

	(anInteger notNil and: [ anInteger < 0 ]) ifTrue: [
		^ self error: 'a negative number of retries cannot be used up' ].
	orphanedRetryLimit := anInteger
]

{ #category : #printing }
SoilQueueDescription >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << name << ' in ' << strategy range printString
]

{ #category : #rate }
SoilQueueDescription >> rateLimit [
	"how many entries may be handed out in any period of #ratePeriod, or nil for no rate at
	all -- the default, and how a queue ran before it had one. A number here is what a far
	side accepts per so long; it is the embedder's to know.

	One rate for the whole queue. Work that needs a pace of its own gets a queue of its own,
	on the same index if need be: queues that differ only in their rate are what segmenting
	a queue is for"

	^ rateLimit
]

{ #category : #rate }
SoilQueueDescription >> rateLimit: anInteger per: aDuration [
	"no more than anInteger entries handed out in any period of aDuration. Any period, not
	the one on the clock: a burst up to the limit may go at once, and then the rate waits
	until the oldest of it is aDuration ago"

	anInteger < 1 ifTrue: [ ^ self error: 'a rate that lets nothing out would stop the queue' ].
	rateLimit := anInteger.
	ratePeriod := aDuration
]

{ #category : #rate }
SoilQueueDescription >> ratePeriod [
	"the length of the period #rateLimit counts in"

	^ ratePeriod
]

{ #category : #removing }
SoilQueueDescription >> removeKey: aKey [
	"take an entry out of the ordering. What the entry itself then says about why -- done,
	failed at its work, dead lettered -- is written in the same transaction"

	^ strategy index removeKey: aKey
]

{ #category : #initialization }
SoilQueueDescription >> setName: aSymbol strategy: aStrategy format: aFormat [

	name := aSymbol.
	strategy := aStrategy.
	format := aFormat
]

{ #category : #accessing }
SoilQueueDescription >> settings [
	"what a queue runs by, taken from me as I stand now. I keep and change the values; the
	queue reads them when it starts"

	^ SoilQueueSettings from: self
]

{ #category : #accessing }
SoilQueueDescription >> strategy [

	^ strategy
]

{ #category : #accessing }
SoilQueueDescription >> workerLimit [
	"how many workers may run at once. One unless the embedder says otherwise, and that is
	the cautious direction: in Pharo processes are green threads, so more of them buy
	overlap during waiting and latency isolation between a long entry and a short one, never
	throughput. Against a backlog the answer is a different rate, not more workers."

	^ workerLimit ifNil: [ 1 ]
]

{ #category : #accessing }
SoilQueueDescription >> workerLimit: anInteger [

	anInteger < 1 ifTrue: [ ^ self error: 'a queue with no worker would never run' ].
	workerLimit := anInteger
]
