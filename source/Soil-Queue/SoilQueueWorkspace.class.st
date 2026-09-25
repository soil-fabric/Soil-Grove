"
What a queue works on: the index its entries lie on, the section of it that is theirs,
the format that orders them, and the dead letters. Everything a queue reads or writes
about its entries goes through me.

A queue is created on me, with or without a resident around it. With one, I am the
resident's workspace: its description holds me and hands my object id to the queue, so
that the queue reaches me directly and the description is read only to create and
configure it. I am a cluster root of my own for that reason -- the description makes me
one when it is initialized.

The index is mine and nobody else's. Its key size and the width of the marker in front
of every key are properties of the index, fixed when I am created: an index cannot
change its key size later, so it has to be the widest key that will ever be needed.

The format belongs here and not to the description because it shapes every key: whoever
opens me without a description still has to find the entries, and that needs the order
they were filed in.
"
Class {
	#name : #SoilQueueWorkspace,
	#superclass : #Object,
	#instVars : [
		'index',
		'range',
		'format',
		'deadLetters'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueWorkspace class >> index: aSoilIndexedDictionary range: aSoilPrefixRange format: aFormat [

	^ self new
		setIndex: aSoilIndexedDictionary
		range: aSoilPrefixRange
		format: aFormat
]

{ #category : #'instance creation' }
SoilQueueWorkspace class >> timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes [
	"the ordinary case: an index of my own, ordered by due time, with no marker and no byte
	paid for one.

	The skip list level is set because Soil leaves it nil, and a nil one fails on the first
	write with a message that says nothing about what is missing. 16 is what the one
	long-lived collection in the wild uses. A B-tree ignores it."

	^ self
		index: ((SoilIndexedDictionary newWithBackend: anIndexClass)
			keySize: keySizeInBytes;
			maxLevel: 16;
			yourself)
		range: (SoilPrefixRange prefix: 0 width: 0 keySize: keySizeInBytes)
		format: SoilQueueTimeOrderedKeyFormat new
]

{ #category : #adding }
SoilQueueWorkspace >> add: anEntry [
	"put an entry in, in the transaction I was read in -- I do not commit. The
	notification that wakes a worker belongs after that commit, not here: before it there
	is nothing to find.

	Answers the key in the form the index compares in, which is the form everything else
	hands around too. #keyFor: answers the other form, the bytes it is composed of."

	| key |
	key := self keyFor: anEntry.
	index at: key put: anEntry.
	^ key asIndexKeyOfSize: range keySize
]

{ #category : #accessing }
SoilQueueWorkspace >> backend [
	"the kind of index my entries lie on, in its durable form. Asked of the persistent
	index and not of the one in hand: a materialized index is wrapped copy-on-write per
	transaction, and that wrapper cannot be used to build a new index with."

	^ index persistentIndex class
]

{ #category : #accessing }
SoilQueueWorkspace >> deadLetter: aKey [
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
SoilQueueWorkspace >> deadLettersDo: aBlock [
	"the parked entries with their keys. Nobody is woken for these -- they are here to be
	looked at"

	deadLetters newIterator associationsDo: [ :each |
		aBlock value: each key value: each value ]
]

{ #category : #accessing }
SoilQueueWorkspace >> dueCountAt: aDateAndTime upTo: aLimit [
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
SoilQueueWorkspace >> entryAt: aKey [

	^ index at: aKey
]

{ #category : #accessing }
SoilQueueWorkspace >> entryAt: aKey ifAbsent: aBlock [

	^ index at: aKey ifAbsent: aBlock
]

{ #category : #accessing }
SoilQueueWorkspace >> format [

	^ format
]

{ #category : #accessing }
SoilQueueWorkspace >> index [

	^ index
]

{ #category : #initialization }
SoilQueueWorkspace >> initializeIn: aTransaction [
	"the objects I hold that are cluster roots of their own, created once, when the
	description I belong to is initialized -- after it has made me a root.

	The index is one: it is not copied into my cluster, and it is written page by page
	rather than with me. An index that is already on disk was put there before and is not
	mine to create again.

	The dead letters get a second index. Out of the ordering, so that a parked entry is not
	stepped over on every scan for work, and still in the store, so that it can be found
	and looked at -- work that disappears without a trace is worse than work that sits there
	unfinished."

	index isPresentOnDisk ifFalse: [ aTransaction makeRoot: index ].
	deadLetters := (SoilIndexedDictionary newWithBackend: self backend)
		keySize: range keySize;
		maxLevel: 16;
		yourself.
	aTransaction makeRoot: deadLetters
]

{ #category : #converting }
SoilQueueWorkspace >> keyFor: anEntry [
	"the chain: the format orders, and my section places the result -- marker first,
	padding last, filling the whole key size.

	No single participant knows the whole key. The entry supplies values and never a key,
	so that two entries of one queue cannot sort by different rules."

	^ range keyWith: (ByteArray streamContents: [ :parts |
		format appendKeyPartsFor: anEntry on: parts ])
]

{ #category : #enumerating }
SoilQueueWorkspace >> keysAndEntriesDo: aBlock [
	"every entry of my section with its key, in key order.

	The only reader of this is the recovery pass, and it reads every entry because that is
	where the answer is: an orphaned claim cannot be found over the index, since a claim
	does not change the key. Selecting work does not come this way -- it reads one entry
	and stops."

	| iterator scanKey found |
	iterator := index newIterator.
	scanKey := range firstIndexKey.
	[ found := iterator nextKeyCloseTo: scanKey.
	  found notNil and: [ range includesKey: found ] ] whileTrue: [
		aBlock value: found value: (iterator at: found).
		scanKey := found + 1 ]
]

{ #category : #moving }
SoilQueueWorkspace >> moveKey: aKey for: anEntry [
	"put anEntry under the key it asks for now, and answer that key. Its due time may have
	changed since it came in -- that is how a follow-up later and a backoff are expressed --
	and the key is what sorts by it. Unchanged, nothing is written.

	One move rather than a removal and an insertion, because the removal answers an
	unloaded proxy and an insertion would resolve it: the target would be read from disk
	only to change the number it is filed under. Asked of the index and not of an iterator
	on it -- the index is the one that writes the journal and marks itself for the commit."

	| newKey |
	newKey := (self keyFor: anEntry) asIndexKeyOfSize: range keySize.
	newKey = aKey ifTrue: [ ^ aKey ].
	index moveKey: aKey to: newKey.
	^ newKey
]

{ #category : #accessing }
SoilQueueWorkspace >> nextDueAt: aDateAndTime skipping: aCollection ifNone: aBlock [
	"the key of the oldest entry that is due, skipping the keys that are already out.

	When nothing is due, aBlock is evaluated with the time the next entry becomes due, or
	with nil when there is nothing at all -- so a caller can sleep exactly as long as it
	has to rather than come back and ask again.

	The scan jumps rather than steps: to the start of my section, then past each key it
	looked at. What ends it is the range, which says where the section stops. Past the last
	key of the index the positioning call answers nil, so that end takes care of itself.

	Only pending entries are handed out. An entry that says claimed belongs to a worker, or
	to the recovery pass if no worker holds it -- and it stays in the ordering either way,
	because a claim does not change a key. Without this a work unit that throws would be
	handed straight back to the next worker, for ever."

	| iterator scanKey found |
	iterator := index newIterator.
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
SoilQueueWorkspace >> nextDueTimeAt: aDateAndTime [
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
SoilQueueWorkspace >> printOn: aStream [

	super printOn: aStream.
	aStream << ' ' << range printString
]

{ #category : #accessing }
SoilQueueWorkspace >> range [
	"the section of the index that is mine: the marker in front of every key, its width,
	and the key size"

	^ range
]

{ #category : #removing }
SoilQueueWorkspace >> removeKey: aKey [
	"take an entry out of the ordering. What the entry itself then says about why -- done,
	failed at its work, dead lettered -- is written in the same transaction"

	^ index removeKey: aKey
]

{ #category : #initialization }
SoilQueueWorkspace >> setIndex: aSoilIndexedDictionary range: aSoilPrefixRange format: aFormat [

	index := aSoilIndexedDictionary.
	range := aSoilPrefixRange.
	format := aFormat
]
