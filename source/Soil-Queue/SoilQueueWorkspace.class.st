"
What a queue works on: the index its entries lie on, the lanes that share it, and the
dead letters. Everything a queue reads or writes about its entries goes through me.

A queue is created on me, with or without a resident around it. With one, I am the
resident's workspace: its description holds me and hands my object id to the queue, so
that the queue reaches me directly and the description is read only to create and
configure it. I am a cluster root of my own for that reason -- the description makes me
one when it is initialized.

The index is mine and nobody else's, and its key size is fixed when I am created: an
index cannot change it later, so it has to be the widest key that will ever be needed.
The lanes share the index. Each has a section of it, told apart by a marker in front of
every key, and a format that orders its keys; both are stored here, as
SoilQueueLaneDescriptions, because they shape every key -- whoever opens me without a
description still has to find the entries. How fast a lane runs is not mine.
"
Class {
	#name : #SoilQueueWorkspace,
	#superclass : #Object,
	#instVars : [
		'index',
		'keySize',
		'lanes',
		'deadLetters'
	],
	#category : #'Soil-Queue'
}

{ #category : #'instance creation' }
SoilQueueWorkspace class >> index: aSoilIndexedDictionary keySize: keySizeInBytes lanes: aCollection [

	^ self new
		setIndex: aSoilIndexedDictionary
		keySize: keySizeInBytes
		lanes: aCollection
]

{ #category : #'instance creation' }
SoilQueueWorkspace class >> timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes [
	"the ordinary case: an index of my own with one lane, #default, ordered by due time,
	with no marker and no byte paid for one.

	The skip list level is set because Soil leaves it nil, and a nil one fails on the first
	write with a message that says nothing about what is missing. 16 is what the one
	long-lived collection in the wild uses. A B-tree ignores it."

	^ self
		index: ((SoilIndexedDictionary newWithBackend: anIndexClass)
			keySize: keySizeInBytes;
			maxLevel: 16;
			yourself)
		keySize: keySizeInBytes
		lanes: { SoilQueueLaneDescription
			named: #default
			range: (SoilPrefixRange prefix: 0 width: 0 keySize: keySizeInBytes)
			format: SoilQueueTimeOrderedKeyFormat new }
]

{ #category : #adding }
SoilQueueWorkspace >> add: anEntry [
	"put an entry into my first lane"

	^ self add: anEntry to: self defaultLane
]

{ #category : #adding }
SoilQueueWorkspace >> add: anEntry to: aLaneDescription [
	"put an entry into a lane, in the transaction I was read in -- I do not commit. The
	notification that wakes a worker belongs after that commit, not here: before it there
	is nothing to find.

	Answers the key in the form the index compares in, which is the form everything else
	hands around too. #keyFor: of the lane answers the other form, the bytes it is composed
	of."

	| key |
	key := aLaneDescription keyFor: anEntry.
	index at: key put: anEntry.
	^ key asIndexKeyOfSize: keySize
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
SoilQueueWorkspace >> defaultLane [
	"my first lane -- the only one until a queue has more"

	^ lanes first
]

{ #category : #accessing }
SoilQueueWorkspace >> dueCountAt: aDateAndTime in: aLaneDescription upTo: aLimit [
	"how many entries of a lane are due, counted no further than aLimit.

	The number is only ever used to decide how many workers to have, so counting past the
	limit would buy nothing. The walk stops at the first entry that is not due either,
	because a lane is ordered by due time and nothing behind it can be due.

	Only pending entries count. One that says claimed is with a worker already, or waiting
	for the recovery pass, and in neither case does it call for another worker."

	| count |
	count := 0.
	aLimit < 1 ifTrue: [ ^ count ].
	self keysAndEntriesIn: aLaneDescription do: [ :key :entry |
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
		keySize: keySize;
		maxLevel: 16;
		yourself.
	aTransaction makeRoot: deadLetters
]

{ #category : #enumerating }
SoilQueueWorkspace >> keysAndEntriesDo: aBlock [
	"every entry of every lane with its key, lane after lane, in key order.

	The only reader of this is the recovery pass, and it reads every entry because that is
	where the answer is: an orphaned claim cannot be found over the index, since a claim
	does not change the key. Selecting work does not come this way -- it reads one entry
	and stops."

	lanes do: [ :each | self keysAndEntriesIn: each do: aBlock ]
]

{ #category : #enumerating }
SoilQueueWorkspace >> keysAndEntriesIn: aLaneDescription do: aBlock [
	"every entry of one lane with its key, in key order -- jumping to the start of the lane's
	section and stopping where it ends"

	| iterator range scanKey found |
	range := aLaneDescription range.
	iterator := index newIterator.
	scanKey := range firstIndexKey.
	[ found := iterator nextKeyCloseTo: scanKey.
	  found notNil and: [ range includesKey: found ] ] whileTrue: [
		aBlock value: found value: (iterator at: found).
		scanKey := found + 1 ]
]

{ #category : #accessing }
SoilQueueWorkspace >> keySize [

	^ keySize
]

{ #category : #accessing }
SoilQueueWorkspace >> laneFor: anIndexKey [
	"the lane a key lies in, found from the key alone: every key carries its lane's marker"

	^ lanes
		detect: [ :each | each includesKey: anIndexKey ]
		ifNone: [ self error: 'a key in none of my lanes: ', anIndexKey printString ]
]

{ #category : #accessing }
SoilQueueWorkspace >> laneNamed: aSymbol [

	^ lanes
		detect: [ :each | each name = aSymbol ]
		ifNone: [ self error: 'no lane named ', aSymbol printString ]
]

{ #category : #accessing }
SoilQueueWorkspace >> lanes [

	^ lanes asArray
]

{ #category : #moving }
SoilQueueWorkspace >> moveKey: aKey for: anEntry [
	"put anEntry under the key it asks for now, in the lane it lies in, and answer that key.
	Its due time may have changed since it came in -- that is how a follow-up later and a
	backoff are expressed -- and the key is what sorts by it. Unchanged, nothing is written.

	One move rather than a removal and an insertion, because the removal answers an
	unloaded proxy and an insertion would resolve it: the target would be read from disk
	only to change the number it is filed under. Asked of the index and not of an iterator
	on it -- the index is the one that writes the journal and marks itself for the commit."

	| newKey |
	newKey := ((self laneFor: aKey) keyFor: anEntry) asIndexKeyOfSize: keySize.
	newKey = aKey ifTrue: [ ^ aKey ].
	index moveKey: aKey to: newKey.
	^ newKey
]

{ #category : #accessing }
SoilQueueWorkspace >> nextDueAt: aDateAndTime in: aLaneDescription skipping: aCollection ifNone: aBlock [
	"the key of the oldest entry of a lane that is due, skipping the keys that are already
	out.

	When nothing is due, aBlock is evaluated with the time the next entry becomes due, or
	with nil when there is nothing at all -- so a caller can sleep exactly as long as it
	has to rather than come back and ask again.

	The scan jumps rather than steps: to the start of the lane's section, then past each key
	it looked at. What ends it is the range, which says where the section stops. Past the
	last key of the index the positioning call answers nil, so that end takes care of
	itself.

	Only pending entries are handed out. An entry that says claimed belongs to a worker, or
	to the recovery pass if no worker holds it -- and it stays in the ordering either way,
	because a claim does not change a key. Without this a work unit that throws would be
	handed straight back to the next worker, for ever."

	| iterator range scanKey found |
	range := aLaneDescription range.
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
SoilQueueWorkspace >> nextDueAt: aDateAndTime skipping: aCollection ifNone: aBlock [
	"the same for my first lane"

	^ self
		nextDueAt: aDateAndTime
		in: self defaultLane
		skipping: aCollection
		ifNone: aBlock
]

{ #category : #accessing }
SoilQueueWorkspace >> nextDueTimeAt: aDateAndTime [
	"when the first entry of any lane may run: aDateAndTime itself when one is already due,
	the time of the earliest one when none is, and nil when no lane holds anything.

	One of the two questions an embedder asks a queue. It answers a time rather than a key
	because the asker is not going to work on it -- it wants to know how long it may sleep,
	or whether the database is quiet enough to close."

	^ lanes
		inject: nil
		into: [ :earliest :each |
			(self nextDueTimeAt: aDateAndTime in: each)
				ifNil: [ earliest ]
				ifNotNil: [ :time |
					earliest ifNil: [ time ] ifNotNil: [ earliest min: time ] ] ]
]

{ #category : #accessing }
SoilQueueWorkspace >> nextDueTimeAt: aDateAndTime in: aLaneDescription [
	"when the first entry of a lane may run: aDateAndTime itself when one is already due,
	the time of the earliest one when none is, and nil when the lane holds nothing"

	self
		nextDueAt: aDateAndTime
		in: aLaneDescription
		skipping: #(  )
		ifNone: [ :time | ^ time ].
	^ aDateAndTime
]

{ #category : #printing }
SoilQueueWorkspace >> printOn: aStream [

	super printOn: aStream.
	lanes do: [ :each | aStream << ' ' << each name ]
]

{ #category : #removing }
SoilQueueWorkspace >> removeKey: aKey [
	"take an entry out of the ordering. What the entry itself then says about why -- done,
	failed at its work, dead lettered -- is written in the same transaction"

	^ index removeKey: aKey
]

{ #category : #initialization }
SoilQueueWorkspace >> setIndex: aSoilIndexedDictionary keySize: keySizeInBytes lanes: aCollection [

	index := aSoilIndexedDictionary.
	keySize := keySizeInBytes.
	lanes := aCollection asOrderedCollection
]
