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
		'deadLetters'
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
SoilQueueDescription >> entryAt: aKey [

	^ strategy index at: aKey
]

{ #category : #accessing }
SoilQueueDescription >> entryAt: aKey ifAbsent: aBlock [

	^ strategy index at: aKey ifAbsent: aBlock
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

{ #category : #accessing }
SoilQueueDescription >> name [

	^ name
]

{ #category : #'instance creation' }
SoilQueueDescription >> newInstanceIn: aTransaction [
	"the name goes along, so the live queue can answer for itself what it is called
	without opening a transaction for a label"

	^ (super newInstanceIn: aTransaction)
		name: name;
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
	call answers nil, so that end takes care of itself."

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
					entry eligibleAt <= aDateAndTime ifTrue: [ ^ found ].
					^ aBlock cull: entry eligibleAt ] ].
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

{ #category : #printing }
SoilQueueDescription >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << name << ' in ' << strategy range printString
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
SoilQueueDescription >> strategy [

	^ strategy
]
