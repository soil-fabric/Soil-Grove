"
The durable half: entries go in, the oldest due one comes back, and a queue keeps its
entries to itself when it shares an index with another.

That last one is what the whole key scheme exists for. Nothing about an index says that
it is shared, so a queue that got its marker or its padding wrong would not fail -- it
would quietly hand out another queue's work.
"
Class {
	#name : #SoilQueueDescriptionTest,
	#superclass : #TestCase,
	#instVars : [
		'soil'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueDescriptionTest >> addQueueNamed: aSymbol [

	^ soil addResidentDescription: (SoilQueueDescription
		named: aSymbol
		timeOrderedWithBackend: SoilSkipList
		keySize: 24)
]

{ #category : #helpers }
SoilQueueDescriptionTest >> addQueueNamed: aSymbol marker: anInteger [
	"a queue that leaves room in front of its keys for other queues on the same index"

	^ soil addResidentDescription: (SoilQueueDescription
		named: aSymbol
		strategy: (SoilQueueStrategy
			on: ((SoilIndexedDictionary newWithBackend: SoilSkipList)
				keySize: 24;
				maxLevel: 16;
				yourself)
			range: (SoilPrefixRange prefix: anInteger width: 1 keySize: 24))
		format: SoilQueueTimeOrderedKeyFormat new)
]

{ #category : #helpers }
SoilQueueDescriptionTest >> addQueueSharingTheIndexOf: aSymbol named: anotherSymbol marker: anInteger [
	"what an embedder does to put a second queue on an existing index: read that index in
	the transaction the new description is written in. The registry work is the embedder's
	either way -- SoilTestResidentDatabase>>addResidentDescription: does the same for a
	queue that brings its own index."

	| txn |
	txn := soil newTransaction.
	^ [ | registry description |
	  registry := soil ensureResidentRegistryIn: txn.
	  description := SoilQueueDescription
		named: anotherSymbol
		strategy: (SoilQueueStrategy
			on: (registry descriptionNamed: aSymbol) strategy index
			range: (SoilPrefixRange prefix: anInteger width: 1 keySize: 24))
		format: SoilQueueTimeOrderedKeyFormat new.
	  registry addDescription: description.
	  txn makeRoot: description.
	  description initializeFrom: txn.
	  txn commit.
	  description ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueDescriptionTest >> description: aSymbol in: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: aSymbol
]

{ #category : #helpers }
SoilQueueDescriptionTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueDescriptionTest >> entryDueIn: aDuration [

	^ (SoilQueueTestEntry on: 'work')
		eligibleAt: DateAndTime now + aDuration;
		yourself
]

{ #category : #accessing }
SoilQueueDescriptionTest >> path [

	^ 'soil-queue-tests'
]

{ #category : #helpers }
SoilQueueDescriptionTest >> put: anEntry [
	"add an entry in a transaction of its own, the way an embedder would"

	| txn |
	txn := soil newTransaction.
	^ [ | key |
	  key := (self descriptionIn: txn) add: anEntry.
	  txn commit.
	  key ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #running }
SoilQueueDescriptionTest >> setUp [

	super setUp.
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot
]

{ #category : #running }
SoilQueueDescriptionTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueDescriptionTest >> testAKeyCarriesTheDueTimeInFrontOfTheId [
	"the ordering rests on this: due time first, so the oldest due entry is the first key
	of the section and finding work is a lookup rather than a search"

	| description entry key |
	description := self addQueueNamed: #work.
	entry := self entryDueIn: 0 seconds.
	key := description keyFor: entry.
	self assert: key size equals: 24.
	self assert: (key copyFrom: 9 to: 16) equals: entry id.
	self
		assert: (key first: 8) asInteger
		equals: (entry eligibleAt - DateAndTime unixEpoch) asMilliSeconds
]

{ #category : #tests }
SoilQueueDescriptionTest >> testAnEmptyQueueHasNoNextTimeToOfferEither [
	"nothing due and nothing coming are different answers, and a caller that sleeps on them
	has to tell them apart: one is a wait, the other is a wait for a notification"

	| txn |
	self addQueueNamed: #work.
	txn := soil newTransaction.
	self
		assert: ((self descriptionIn: txn)
			nextDueAt: DateAndTime now
			skipping: #(  )
			ifNone: [ :time | time ])
		equals: nil.
	txn abort
]

{ #category : #tests }
SoilQueueDescriptionTest >> testEntriesComeOutOldestDueFirst [

	| txn early |
	self addQueueNamed: #work.
	self put: (self entryDueIn: 10 seconds).
	early := self put: (self entryDueIn: 1 seconds).

	txn := soil newTransaction.
	self
		assert: ((self descriptionIn: txn)
			nextDueAt: DateAndTime now + 1 minute
			skipping: #(  )
			ifNone: [ nil ])
		equals: early.
	txn abort
]

{ #category : #tests }
SoilQueueDescriptionTest >> testNothingDueAnswersWhenTheNextOneIs [
	"so a caller sleeps exactly as long as it has to instead of coming back to ask"

	| txn due |
	self addQueueNamed: #work.
	due := DateAndTime now + 1 hour.
	self put: ((self entryDueIn: 0 seconds) eligibleAt: due; yourself).

	txn := soil newTransaction.
	self
		assert: ((self descriptionIn: txn)
			nextDueAt: DateAndTime now
			skipping: #(  )
			ifNone: [ :time | time ])
		equals: due.
	txn abort
]

{ #category : #tests }
SoilQueueDescriptionTest >> testTakingAnEntryOutLeavesTheNextOne [

	| txn first second |
	self addQueueNamed: #work.
	first := self put: (self entryDueIn: 0 seconds).
	second := self put: (self entryDueIn: 1 seconds).

	txn := soil newTransaction.
	(self descriptionIn: txn) removeKey: first.
	txn commit.

	txn := soil newTransaction.
	self
		assert: ((self descriptionIn: txn)
			nextDueAt: DateAndTime now + 1 minute
			skipping: #(  )
			ifNone: [ nil ])
		equals: second.
	txn abort
]

{ #category : #tests }
SoilQueueDescriptionTest >> testTheDescriptionBringsItsParametersBackFromDisk [
	"it carries them itself, so a queue works wherever it turns up"

	| txn readBack |
	self addQueueNamed: #work.
	txn := soil newTransaction.
	readBack := self descriptionIn: txn.
	self assert: readBack name equals: #work.
	self assert: readBack format class equals: SoilQueueTimeOrderedKeyFormat.
	self assert: readBack strategy range keySize equals: 24.
	self assert: readBack strategy range width equals: 0.
	txn abort
]

{ #category : #tests }
SoilQueueDescriptionTest >> testTwoQueuesOnOneIndexDoNotSeeEachOther [
	"the reason every key carries a marker. The index has no idea that it is shared, so a
	queue that got its marker or its padding wrong would hand out the other one's work
	rather than fail"

	| txn firstKey secondKey |
	self addQueueNamed: #first marker: 1.
	self addQueueSharingTheIndexOf: #first named: #second marker: 2.

	txn := soil newTransaction.
	firstKey := (self description: #first in: txn) add: (self entryDueIn: 0 seconds).
	secondKey := (self description: #second in: txn) add: (self entryDueIn: 0 seconds).
	txn commit.

	txn := soil newTransaction.
	self
		assert: ((self description: #first in: txn)
			nextDueAt: DateAndTime now + 1 minute
			skipping: #(  )
			ifNone: [ nil ])
		equals: firstKey.
	self
		assert: ((self description: #second in: txn)
			nextDueAt: DateAndTime now + 1 minute
			skipping: #(  )
			ifNone: [ nil ])
		equals: secondKey.
	txn abort
]
