"
Where a queue's entries are: entries go in, the oldest due one comes back, the next due
time can be asked for, and the shape of the index comes back from disk.

This is the workspace -- what a queue works on, with or without a resident around it.
Until 2026-09-25 these were the description's tests, and they included two queues on one
index; that case is gone, the index belongs to one queue, and keeping sections of it
apart is the lanes' business.
"
Class {
	#name : #SoilQueueWorkspaceTest,
	#superclass : #TestCase,
	#instVars : [
		'soil'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueWorkspaceTest >> addQueueNamed: aSymbol [

	^ soil addResidentDescription: (SoilQueueDescription
		named: aSymbol
		timeOrderedWithBackend: SoilSkipList
		keySize: 24)
]

{ #category : #helpers }
SoilQueueWorkspaceTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueWorkspaceTest >> workspaceIn: aTransaction [
	"where the entries are: the workspace the description holds"

	^ (self descriptionIn: aTransaction) workspace
]

{ #category : #helpers }
SoilQueueWorkspaceTest >> entryDueIn: aDuration [

	^ (SoilQueueTestEntry on: 'work')
		eligibleAt: DateAndTime now + aDuration;
		yourself
]

{ #category : #accessing }
SoilQueueWorkspaceTest >> path [

	^ 'soil-queue-tests'
]

{ #category : #helpers }
SoilQueueWorkspaceTest >> put: anEntry [
	"add an entry in a transaction of its own, the way an embedder would"

	| txn |
	txn := soil newTransaction.
	^ [ | key |
	  key := (self workspaceIn: txn) add: anEntry.
	  txn commit.
	  key ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #running }
SoilQueueWorkspaceTest >> setUp [

	super setUp.
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot
]

{ #category : #running }
SoilQueueWorkspaceTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueWorkspaceTest >> testAKeyCarriesTheDueTimeInFrontOfTheId [
	"the ordering rests on this: due time first, so the oldest due entry is the first key
	of the section and finding work is a lookup rather than a search"

	| description entry key |
	description := self addQueueNamed: #work.
	entry := self entryDueIn: 0 seconds.
	key := description workspace keyFor: entry.
	self assert: key size equals: 24.
	self assert: (key copyFrom: 9 to: 16) equals: entry id.
	self
		assert: (key first: 8) asInteger
		equals: (entry eligibleAt - DateAndTime unixEpoch) asMilliSeconds
]

{ #category : #tests }
SoilQueueWorkspaceTest >> testAnEmptyQueueHasNoNextTimeToOfferEither [
	"nothing due and nothing coming are different answers, and a caller that sleeps on them
	has to tell them apart: one is a wait, the other is a wait for a notification"

	| txn |
	self addQueueNamed: #work.
	txn := soil newTransaction.
	self
		assert: ((self workspaceIn: txn)
			nextDueAt: DateAndTime now
			skipping: #(  )
			ifNone: [ :time | time ])
		equals: nil.
	txn abort
]

{ #category : #tests }
SoilQueueWorkspaceTest >> testEntriesComeOutOldestDueFirst [

	| txn early |
	self addQueueNamed: #work.
	self put: (self entryDueIn: 10 seconds).
	early := self put: (self entryDueIn: 1 seconds).

	txn := soil newTransaction.
	self
		assert: ((self workspaceIn: txn)
			nextDueAt: DateAndTime now + 1 minute
			skipping: #(  )
			ifNone: [ nil ])
		equals: early.
	txn abort
]

{ #category : #tests }
SoilQueueWorkspaceTest >> testNothingDueAnswersWhenTheNextOneIs [
	"so a caller sleeps exactly as long as it has to instead of coming back to ask"

	| txn due |
	self addQueueNamed: #work.
	due := DateAndTime now + 1 hour.
	self put: ((self entryDueIn: 0 seconds) eligibleAt: due; yourself).

	txn := soil newTransaction.
	self
		assert: ((self workspaceIn: txn)
			nextDueAt: DateAndTime now
			skipping: #(  )
			ifNone: [ :time | time ])
		equals: due.
	txn abort
]

{ #category : #tests }
SoilQueueWorkspaceTest >> testTakingAnEntryOutLeavesTheNextOne [

	| txn first second |
	self addQueueNamed: #work.
	first := self put: (self entryDueIn: 0 seconds).
	second := self put: (self entryDueIn: 1 seconds).

	txn := soil newTransaction.
	(self workspaceIn: txn) removeKey: first.
	txn commit.

	txn := soil newTransaction.
	self
		assert: ((self workspaceIn: txn)
			nextDueAt: DateAndTime now + 1 minute
			skipping: #(  )
			ifNone: [ nil ])
		equals: second.
	txn abort
]

{ #category : #tests }
SoilQueueWorkspaceTest >> testTheWorkspaceBringsItsShapeBackFromDisk [
	"the workspace carries its index's shape itself -- key size, marker width, format --
	so a queue created on it works wherever it turns up"

	| txn workspace |
	self addQueueNamed: #work.
	txn := soil newTransaction.
	workspace := self workspaceIn: txn.
	self assert: workspace format class equals: SoilQueueTimeOrderedKeyFormat.
	self assert: workspace range keySize equals: 24.
	self assert: workspace range width equals: 0.
	txn abort
]

{ #category : #tests }
SoilQueueWorkspaceTest >> testTheWorkspaceIsAClusterRootOfItsOwn [
	"what lets the resident reach it by id, without reading its description"

	| txn description |
	self addQueueNamed: #work.
	txn := soil newTransaction.
	description := self descriptionIn: txn.
	self assert: description workspaceId notNil.
	self assert: ((txn objectWithId: description workspaceId) isKindOf: SoilQueueWorkspace).
	txn abort
]

