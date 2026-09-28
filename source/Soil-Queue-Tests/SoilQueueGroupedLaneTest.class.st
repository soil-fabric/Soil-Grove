"
A grouped lane keeps the entries of each group in the order they came in: its key is the
group, then a sequence number within it, then the entry's id.

These are the keys only. Which entry of a lane goes out, and that only one of a group is
out at a time, is the queue's part and tested with it.
"
Class {
	#name : #SoilQueueGroupedLaneTest,
	#superclass : #TestCase,
	#instVars : [
		'soil'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueGroupedLaneTest >> entryIn: aGroup [

	^ (SoilQueueTestEntry on: 'work')
		groupId: aGroup;
		yourself
]

{ #category : #helpers }
SoilQueueGroupedLaneTest >> inTransaction: aBlock [

	| txn |
	txn := soil newTransaction.
	^ [ | answer |
	  answer := aBlock value: txn.
	  txn commit.
	  answer ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueGroupedLaneTest >> keysOfGroupsLane [
	"the keys of the grouped lane in key order, as bytes"

	| txn keys |
	txn := soil newTransaction.
	keys := OrderedCollection new.
	[ | workspace |
	  workspace := self workspaceIn: txn.
	  workspace
		keysAndEntriesIn: (workspace laneNamed: #groups)
		do: [ :key :entry | keys add: (key asByteArrayOfSize: 24) ] ]
		ensure: [ txn abort ].
	^ keys
]

{ #category : #helpers }
SoilQueueGroupedLaneTest >> lane: aTransaction [

	^ (self workspaceIn: aTransaction) laneNamed: #groups
]

{ #category : #accessing }
SoilQueueGroupedLaneTest >> path [

	^ 'soil-queue-grouped-lane-tests'
]

{ #category : #helpers }
SoilQueueGroupedLaneTest >> put: anEntry [

	^ self inTransaction: [ :txn |
		(self workspaceIn: txn) add: anEntry to: (self lane: txn) ]
]

{ #category : #helpers }
SoilQueueGroupedLaneTest >> sequenceIn: aKey [
	"behind a marker of one byte and a group id of eight"

	^ (aKey copyFrom: 10 to: 13) asInteger
]

{ #category : #running }
SoilQueueGroupedLaneTest >> setUp [

	super setUp.
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	self inTransaction: [ :txn |
		| workspace |
		workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 24 markerWidth: 1.
		txn root at: #queue put: workspace.
		txn makeRoot: workspace.
		workspace initializeIn: txn.
		workspace addLaneNamed: #groups format: SoilQueueGroupedKeyFormat new ]
]

{ #category : #running }
SoilQueueGroupedLaneTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testAGroupContinuesWhereItsLastEntryLeftOff [
	"what a transaction reads as the last of the group is what an earlier one committed"

	self put: (self entryIn: 7).
	self put: (self entryIn: 7).
	self put: (self entryIn: 7).
	self
		assert: (self keysOfGroupsLane collect: [ :each | self sequenceIn: each ]) asArray
		equals: #( 1 2 3 )
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testAKeyCarriesTheGroupThenItsPlaceInItThenTheId [

	| entry key |
	entry := self entryIn: 7.
	key := (self put: entry) asByteArrayOfSize: 24.
	self assert: key first equals: 1.
	self assert: (key copyFrom: 2 to: 9) equals: (7 asByteArrayOfSize: 8).
	self assert: (self sequenceIn: key) equals: 1.
	self assert: (key copyFrom: 14 to: 21) equals: entry id.
	self assert: (key copyFrom: 22 to: 24) equals: #[ 0 0 0 ]
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testALaneWhoseKeysDoNotFitIsRefused [
	"twenty bytes of grouped key behind a marker of one do not fit into sixteen, and that
	is said when the lane comes in rather than when its first entry does"

	| workspace |
	workspace := SoilQueueWorkspace timeOrderedWithBackend: SoilSkipList keySize: 16 markerWidth: 1.
	self
		should: [ workspace addLaneNamed: #groups format: SoilQueueGroupedKeyFormat new ]
		raise: Error.
	self assert: workspace lanes size equals: 1
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testAnEntryOfAGroupStaysPutWhenItsDueTimeChanges [
	"the due time is not in the key, so a backoff leaves the entry at the head of its group
	instead of moving it behind the ones after it"

	| first key |
	first := self entryIn: 7.
	key := self put: first.
	self put: (self entryIn: 7).
	self inTransaction: [ :txn |
		| workspace entry |
		workspace := self workspaceIn: txn.
		entry := workspace entryAt: key.
		entry eligibleAt: entry eligibleAt + 1 hour.
		self assert: (workspace moveKey: key for: entry) equals: key ].
	self assert: (self keysOfGroupsLane first asIndexKeyOfSize: 24) equals: key
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testAnEntryWithoutAGroupIsRefused [

	self should: [ self put: (SoilQueueTestEntry on: 'work') ] raise: Error.
	self assert: self keysOfGroupsLane isEmpty
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testEachGroupCountsForItself [

	self put: (self entryIn: 7).
	self put: (self entryIn: 8).
	self put: (self entryIn: 7).
	self
		assert: (self keysOfGroupsLane collect: [ :each |
			((each copyFrom: 2 to: 9) asInteger) -> (self sequenceIn: each) ]) asArray
		equals: { 7 -> 1. 7 -> 2. 8 -> 1 }
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testEntriesAddedInOneTransactionKeepTheirOrder [
	"the steps of a chain are often added together, and a transaction sees what it added
	itself"

	| entries |
	entries := (1 to: 3) collect: [ :each | self entryIn: 7 ].
	self inTransaction: [ :txn |
		entries do: [ :each | (self workspaceIn: txn) add: each to: (self lane: txn) ] ].
	self
		assert: (self keysOfGroupsLane collect: [ :each | each copyFrom: 14 to: 21 ]) asArray
		equals: (entries collect: [ :each | each id ]) asArray
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testTheNextEntryComesAfterTheRestWhenTheFirstIsGone [
	"a group is numbered from what it holds, so when its first entry is done the next one
	still goes behind the rest"

	| first |
	first := self put: (self entryIn: 7).
	self put: (self entryIn: 7).
	self inTransaction: [ :txn | (self workspaceIn: txn) removeKey: first ].
	self put: (self entryIn: 7).
	self
		assert: (self keysOfGroupsLane collect: [ :each | self sequenceIn: each ]) asArray
		equals: #( 2 3 )
]

{ #category : #tests }
SoilQueueGroupedLaneTest >> testTwoTransactionsAddingToOneGroupAtOnceKeepBothEntries [
	"both see the same last entry and draw the same number. An index lets the second
	commit overwrite the first under the same key without a word; the id behind the number
	is what keeps both"

	| one other |
	self put: (self entryIn: 7).
	one := soil newTransaction.
	other := soil newTransaction.
	[ (self workspaceIn: one) add: (self entryIn: 7) to: (self lane: one).
	  (self workspaceIn: other) add: (self entryIn: 7) to: (self lane: other).
	  one commit.
	  other commit ]
		ensure: [
			one isAborted ifFalse: [ one abort ].
			other isAborted ifFalse: [ other abort ] ].
	self
		assert: (self keysOfGroupsLane collect: [ :each | self sequenceIn: each ]) asArray
		equals: #( 1 2 2 )
]

{ #category : #helpers }
SoilQueueGroupedLaneTest >> workspaceIn: aTransaction [

	^ aTransaction root at: #queue
]
