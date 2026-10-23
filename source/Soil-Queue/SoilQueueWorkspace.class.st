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

How a lane is read -- which entry is due next, how many are, where an entry goes when its
due time changes -- is the lane's format's. I walk the index for it, in one scan that
goes where the format says (#scanFrom:to:do:), and never ask which kind of format a lane
has.

How wide the marker is, is decided when I am created, and with it how many lanes I can
hold: none wide means one lane over the whole index, one byte means up to 256. A lane
comes in by #addLaneNamed:format:, and I hand out its marker -- the lowest free one. No
lane goes out again.
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
SoilQueueWorkspace class >> newIndexWithBackend: anIndexClass keySize: keySizeInBytes [
	"an index the way both of mine are made: for my entries and for the dead letters.

	The skip list level is set because Soil leaves it nil, and a nil one fails on the first
	write with a message that says nothing about what is missing. 16 is what the one
	long-lived collection in the wild uses. A B-tree ignores it."

	^ (SoilIndexedDictionary newWithBackend: anIndexClass)
		keySize: keySizeInBytes;
		maxLevel: 16;
		yourself
]

{ #category : #'instance creation' }
SoilQueueWorkspace class >> timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes [
	"the ordinary case: an index of my own with one lane, #default, ordered by due time,
	with no marker and no byte paid for one -- and no room for a second lane"

	^ self
		timeOrderedWithBackend: anIndexClass
		keySize: keySizeInBytes
		markerWidth: 0
]

{ #category : #'instance creation' }
SoilQueueWorkspace class >> timeOrderedWithBackend: anIndexClass keySize: keySizeInBytes markerWidth: widthInBytes [
	"an index of my own with one lane, #default, ordered by due time, behind a marker of
	widthInBytes -- room for more lanes to be added, one per marker. Whether that room is
	needed is decided here: the width shapes every key and cannot change later. The dead
	letters get an index of the same kind and key size"

	^ self new
		setIndex: (self newIndexWithBackend: anIndexClass keySize: keySizeInBytes)
		deadLetters: (self newIndexWithBackend: anIndexClass keySize: keySizeInBytes)
		keySize: keySizeInBytes
		lanes: { SoilQueueLaneDescription
			named: #default
			range: (SoilPrefixRange prefix: 0 width: widthInBytes keySize: keySizeInBytes)
			format: SoilQueueTimeOrderedKeyFormat new }
]

{ #category : #adding }
SoilQueueWorkspace >> add: anEntry to: aLaneDescription [
	"put an entry into a lane, in the transaction I was read in -- I do not commit. The
	notification that wakes a worker belongs after that commit, not here: before it there
	is nothing to find.

	The entry says when it may run from, and one that does not is refused. That time decides
	when it is due -- on a lane ordered by due time it sorts it, too -- and when nobody else
	has set it, it is the queue's to set, by the queue's clock
	(SoilQueue>>#add:to:in:). Set here it would be the wall clock past a queue that has a
	clock of its own -- for a queue driven by a test clock, an entry that is never due.

	Answers the key in the form the index compares in, which is the form everything else
	hands around too. #keyFor:in: of the lane answers the other form, the bytes it is
	composed of."

	| key |
	anEntry readyAt ifNil: [
		^ self error: anEntry printString , ' says nothing about when it may run' ].
	key := aLaneDescription keyFor: anEntry in: self.
	index at: key put: anEntry.
	^ key asIndexKeyOfSize: keySize
]

{ #category : #lanes }
SoilQueueWorkspace >> addLaneNamed: aSymbol format: aFormat [
	"a lane behind the lowest marker no lane has, and answer it. The caller never picks a
	marker, so two lanes cannot collide on one, and a lane keeps its marker -- it is written
	into every key of it. No lane is taken out again, so no marker is freed. A gap below the
	last one -- in a workspace stored while lanes could still be taken out -- is filled
	first, and nothing lies under it.

	Stored with me, in the transaction I was read in; I do not commit"

	| width taken prefix lane |
	(lanes anySatisfy: [ :each | each name = aSymbol ]) ifTrue: [
		^ self error: 'there is a lane named ' , aSymbol printString , ' already' ].
	width := self markerWidth.
	aFormat partsSize > (keySize - width) ifTrue: [
		^ self error: 'keys of ' , aFormat partsSize printString , ' bytes do not fit behind a marker of '
			, width printString , ' in a key size of ' , keySize printString ].
	taken := (lanes collect: [ :each | each range prefix ]) asSet.
	prefix := (0 to: (256 raisedTo: width) - 1)
		detect: [ :each | (taken includes: each) not ]
		ifNone: [ ^ self error: 'no marker left for another lane, with markers '
			, width printString , ' bytes wide' ].
	lane := SoilQueueLaneDescription
		named: aSymbol
		range: (SoilPrefixRange prefix: prefix width: width keySize: keySize)
		format: aFormat.
	lanes add: lane.
	^ lane
]

{ #category : #accessing }
SoilQueueWorkspace >> deadLetter: aKey [
	"park an entry that could not be worked on at all, and take it out of the ordering.

	Put first and removed second, so that an abort in between leaves it where it was rather
	than nowhere. It keeps its key: it is the same entry, only somewhere else. It keeps its
	claim too. Being here is what says it is parked, and the claim says when its last
	attempt began; nobody hands out what lies here. Should one ever be taken back into the
	ordering, it goes back unclaimed."

	| entry |
	entry := self entryAt: aKey.
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
SoilQueueWorkspace >> dueAt: aDateAndTime in: aLaneDescription skipping: aCollection upTo: aLimit do: aBlock [
	"how many entries of a lane are due, leaving out the keys in aCollection and counting no
	further than aLimit, and when the next one after aDateAndTime falls due -- both handed to
	aBlock, from one read.

	The number is only ever used to decide how many workers to start, so counting past the
	limit would buy nothing. How the lane is walked for it is its format's to say"

	aLimit < 1 ifTrue: [ ^ aBlock value: 0 value: nil ].
	^ aLaneDescription format
		dueIn: aLaneDescription
		of: self
		at: aDateAndTime
		skipping: aCollection
		upTo: aLimit
		do: aBlock
]

{ #category : #accessing }
SoilQueueWorkspace >> entryAt: aKey [

	^ index at: aKey
]

{ #category : #accessing }
SoilQueueWorkspace >> entryAt: aKey ifAbsent: aBlock [

	^ index at: aKey ifAbsent: aBlock
]

{ #category : #initialization }
SoilQueueWorkspace >> initializeIn: aTransaction [
	"make the two indexes I was created with cluster roots of their own, once, when the
	description I belong to is initialized -- after it has made me a root. An index is not
	copied into my cluster; it is written page by page rather than with me.

	The dead letters have the second one. Out of the ordering, so that a parked entry is
	not stepped over on every scan for work, and still in the store, so that it can be
	found and looked at -- work that disappears without a trace is worse than work that
	sits there unfinished."

	aTransaction makeRoot: index.
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

	| range |
	range := aLaneDescription range.
	self
		scanFrom: range firstIndexKey
		to: range lastIndexKey
		do: [ :key :entryBlock |
			aBlock value: key value: entryBlock value.
			key + 1 ]
]

{ #category : #accessing }
SoilQueueWorkspace >> keySize [

	^ keySize
]

{ #category : #accessing }
SoilQueueWorkspace >> lastKeyFrom: aFirstKey to: aLastKey [
	"the last key between two keys, both included, in the transaction I was read in -- its
	own additions counted, its own removals not -- or nil when there is none. As bytes of
	my key size, for a format to read its parts out of.

	First a jump to the start to see whether anything is there at all, then one past the
	end and a step back. The step back needs a position to step back from, and an index
	with nothing in it has none; the first jump rules that out."

	| iterator first last found |
	first := aFirstKey asIndexKeyOfSize: keySize.
	last := aLastKey asIndexKeyOfSize: keySize.
	iterator := index newIterator.
	found := iterator nextKeyCloseTo: first.
	(found isNil or: [ found > last ]) ifTrue: [ ^ nil ].
	iterator nextKeyCloseTo: last + 1.
	^ iterator previousAssociation key asByteArrayOfSize: keySize
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

{ #category : #accessing }
SoilQueueWorkspace >> markerWidth [
	"how many bytes in front of every key tell the lanes apart -- the same for all of them,
	so any lane answers it. Zero leaves room for one lane only"

	^ self defaultLane range width
]

{ #category : #moving }
SoilQueueWorkspace >> moveKey: aKey for: anEntry [
	"put anEntry under the key it asks for now, in the lane it lies in, and answer that key.
	Its due time may have changed since it came in -- that is how a follow-up later and a
	backoff are expressed -- and the key is what sorts by it. Unchanged, nothing is written.

	One move rather than a removal and an insertion, because the removal answers an
	unloaded proxy and an insertion would resolve it: the target would be read from disk
	only to change the number it is filed under. Asked of the index and not of an iterator
	on it -- the index is the one that writes the journal and marks itself for the commit.

	Which key that is, is the lane's format's to say. One whose keys carry no due time
	answers the key the entry has: it waits where it is, and its due time is read from it."

	| lane newKey |
	lane := self laneFor: aKey.
	newKey := lane format keyFor: anEntry movedFrom: aKey in: lane of: self.
	newKey = aKey ifTrue: [ ^ aKey ].
	index moveKey: aKey to: newKey.
	^ newKey
]

{ #category : #accessing }
SoilQueueWorkspace >> nextDueAt: aDateAndTime in: aLaneDescription skipping: aCollection ifNone: aBlock [
	"the key of the next entry of a lane that is due, skipping the keys that are already
	out -- with no group to prefer and no place to start from"

	^ self
		nextDueAt: aDateAndTime
		in: aLaneDescription
		skipping: aCollection
		preferring: nil
		after: nil
		ifNone: aBlock
]

{ #category : #accessing }
SoilQueueWorkspace >> nextDueAt: aDateAndTime in: aLaneDescription skipping: aCollection preferring: aPreferredKey after: aLastKey ifNone: aBlock [
	"the key of the next entry of a lane that is due, skipping the keys that are already
	out. When nothing is due, aBlock is evaluated with the time the next entry becomes due,
	or with nil when there is nothing at all.

	Which entry that is, is the lane's format's to say: the oldest due one on a lane ordered
	by due time, the first of a group on a grouped lane -- preferring the group of
	aPreferredKey, a worker carrying on with its own chain, and otherwise taking the groups
	in turn from behind that of aLastKey. Either key may be nil."

	^ aLaneDescription format
		nextDueIn: aLaneDescription
		of: self
		at: aDateAndTime
		skipping: aCollection
		preferring: aPreferredKey
		after: aLastKey
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
	"take an entry out of the ordering. Nothing is written on the entry for it: why it left
	-- done, failed at its work, parked -- is not the entry's to say. A parked one lies in
	the dead letters, and the others are gone"

	^ index removeKey: aKey
]

{ #category : #enumerating }
SoilQueueWorkspace >> scanFrom: aFirstIndexKey to: aLastIndexKey do: aBlock [
	"walk the keys between two keys, both included, in key order -- the one walk that reads
	a lane forward; #lastKeyFrom:to: is the one that steps back, from the end of a run.
	aBlock gets a key and a block that reads its entry, and answers the key to go on from:
	the key plus one to step, a key further on to jump past what lies between, nil to stop.

	The entry is read only where it is asked for. Reading it looks the key up a second time,
	and a key that is passed by -- one that is out, say -- should not cost that. The walk
	ends where the keys do: past aLastIndexKey, or past the last key of the index, where the
	positioning call answers nil"

	| iterator scanKey found |
	iterator := index newIterator.
	scanKey := aFirstIndexKey.
	[ scanKey notNil
		and: [ scanKey <= aLastIndexKey
		and: [ (found := iterator nextKeyCloseTo: scanKey) notNil
		and: [ found <= aLastIndexKey ] ] ] ]
		whileTrue: [ scanKey := aBlock value: found value: [ iterator at: found ] ]
]

{ #category : #initialization }
SoilQueueWorkspace >> setIndex: aSoilIndexedDictionary deadLetters: anotherSoilIndexedDictionary keySize: keySizeInBytes lanes: aCollection [

	index := aSoilIndexedDictionary.
	deadLetters := anotherSoilIndexedDictionary.
	keySize := keySizeInBytes.
	lanes := aCollection asOrderedCollection
]
