"
The live half: the part a database object cannot do.

It remembers which entries are out, so the same one is not handed to two workers -- and
that only holds because there is one of it, which is exactly why it is not stored. The
first test here is the one that fails without that: two queues built on the same
description each keep their own set, and hand out the same entry twice.

The rest is a work unit and its transaction boundaries. Select, claim, work: three
transactions, so that a crash between them leaves an entry that says claimed with nobody
working on it, which is what the cleanup afterwards reads.
"
Class {
	#name : #SoilQueueTest,
	#superclass : #TestCase,
	#instVars : [
		'soil',
		'description'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueTest >> entryDueIn: aDuration [

	^ (SoilQueueTestEntry on: 'work')
		eligibleAt: DateAndTime now + aDuration;
		yourself
]

{ #category : #accessing }
SoilQueueTest >> path [

	^ 'soil-queue-tests'
]

{ #category : #helpers }
SoilQueueTest >> put: anEntry [

	| txn |
	txn := soil newTransaction.
	^ [ | key |
	  key := (self descriptionIn: txn) add: anEntry.
	  txn commit.
	  key ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueTest >> queue [
	"a live queue on the description, the way a supervisor would build one. It gets a
	supervisor but is never started: that is the standalone case, and it is the one where
	a work unit can be driven a step at a time"

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueTest >> setUp [

	super setUp.
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	description := soil addResidentDescription: (SoilQueueDescription
		named: #work
		timeOrderedWithBackend: SoilSkipList
		keySize: 24)
]

{ #category : #running }
SoilQueueTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueTest >> testAFinishedWorkUnitLeavesTheOrdering [

	| queue key txn |
	key := self put: (self entryDueIn: 0 seconds).
	queue := self queue.
	queue runStep.

	self deny: (queue isHolding: key).
	txn := soil newTransaction.
	self
		assert: ((self descriptionIn: txn) entryAt: key ifAbsent: [ #gone ])
		equals: #gone.
	txn abort
]

{ #category : #tests }
SoilQueueTest >> testATakenEntryComesBackAfterItIsReleased [

	| queue txn key again |
	key := self put: (self entryDueIn: 0 seconds).
	queue := self queue.

	txn := soil newTransaction.
	queue assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	self assert: (queue isHolding: key).
	queue release: key.
	self deny: (queue isHolding: key).
	again := queue assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	txn abort.

	self assert: again equals: key
]

{ #category : #tests }
SoilQueueTest >> testAWorkUnitClaimsBeforeItWorks [
	"the claim is committed before the work, so that a crash in the middle is visible
	afterwards as an entry that says claimed with nobody working on it"

	| queue key txn |
	key := self put: (self entryDueIn: 0 seconds).
	queue := self queue.
	queue claim: key.

	txn := soil newTransaction.
	self assert: ((self descriptionIn: txn) entryAt: key) isClaimed.
	self assert: ((self descriptionIn: txn) entryAt: key) claimedAt notNil.
	txn abort
]

{ #category : #tests }
SoilQueueTest >> testAnEntryIsHandedOutOnlyOnce [
	"the whole reason the coordinating half is one object in memory"

	| queue txn first second |
	self put: (self entryDueIn: 0 seconds).
	self put: (self entryDueIn: 0 seconds).
	queue := self queue.

	txn := soil newTransaction.
	first := queue assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	second := queue assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	txn abort.

	self assert: first notNil.
	self assert: second notNil.
	self deny: first = second
]

{ #category : #tests }
SoilQueueTest >> testNothingDueLeavesTheStepWithNothingTaken [

	| queue key |
	key := self put: (self entryDueIn: 1 hour).
	queue := self queue.
	queue runStep.
	self deny: (queue isHolding: key)
]

{ #category : #tests }
SoilQueueTest >> testTwoQueuesOnOneDescriptionDoNotKnowOfEachOther [
	"what the first test would look like if the coordinating half were stored: each
	transaction would materialize a queue of its own, and neither would know what the
	other handed out. Pinned down here so that a later change back is a failing test and
	not a duplicated work unit in production."

	| one other txn first second |
	self put: (self entryDueIn: 0 seconds).
	one := self queue.
	other := self queue.
	self deny: one == other.

	txn := soil newTransaction.
	first := one assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	second := other assignNextDueAt: DateAndTime now in: txn ifNone: [ nil ].
	txn abort.

	self assert: first equals: second
]
