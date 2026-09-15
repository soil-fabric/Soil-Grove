"
What happens to an entry the queue cannot work on at all.

Dead lettering is reserved for that and kept apart from failing *at* the work, which is a
result and ends the entry the ordinary way. The two look alike from the outside -- both
leave the ordering -- and what separates them is where the entry ends up: a dead letter
is parked and can still be looked at, a finished entry is done with.

Parked means out of the working ordering and into a store of its own. Out, so that it is
not stepped over on every scan for work; into, so that work does not disappear without a
trace.
"
Class {
	#name : #SoilQueueDeadLetterTest,
	#superclass : #TestCase,
	#instVars : [
		'soil'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #helpers }
SoilQueueDeadLetterTest >> deadLetteredKeys [

	| txn keys |
	txn := soil newTransaction.
	keys := OrderedCollection new.
	^ [ (self descriptionIn: txn)
		deadLettersDo: [ :key :entry | keys add: key -> entry state ].
	  keys asArray ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #accessing }
SoilQueueDeadLetterTest >> path [

	^ 'soil-queue-tests'
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> put: anEntry [

	| txn |
	txn := soil newTransaction.
	^ [ | key |
	  key := (self descriptionIn: txn) add: anEntry.
	  txn commit.
	  key ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		supervisor: soil newResidentSupervisor;
		yourself ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueDeadLetterTest >> setUp [

	super setUp.
	soil := SoilTestResidentDatabase path: self path.
	soil
		destroy;
		initializeFilesystem;
		initializeRoot.
	soil addResidentDescription: (SoilQueueDescription
		named: #work
		timeOrderedWithBackend: SoilSkipList
		keySize: 24)
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> stateOf: aKey [

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) entryAt: aKey ifAbsent: [ nil ])
		ifNotNil: [ :entry | entry state ] ]
		ensure: [ txn abort ]
]

{ #category : #running }
SoilQueueDeadLetterTest >> tearDown [

	soil ifNotNil: [ soil close ].
	super tearDown
]

{ #category : #tests }
SoilQueueDeadLetterTest >> testADeadLetterIsNotHandedOutAgain [
	"out of the ordering, so no scan for work steps over it and no worker takes it"

	| key queue |
	key := self put: (SoilQueueTestUnreachableEntry on: 'gone').
	self workOffEverything.
	queue := self queue.

	self assert: queue nextDueTime equals: nil.
	self deny: (queue isHolding: key)
]

{ #category : #tests }
SoilQueueDeadLetterTest >> testADeadLetterIsParkedWhereItCanBeFound [
	"work that disappears without a trace is worse than work that sits there unfinished"

	| key |
	key := self put: (SoilQueueTestUnreachableEntry on: 'gone').
	self workOffEverything.

	self assert: (self stateOf: key) equals: nil.
	self assert: self deadLetteredKeys equals: { key -> #deadLetter }
]

{ #category : #tests }
SoilQueueDeadLetterTest >> testATargetThatWasNeverSetIsNotGone [
	"never had one is not the same as lost one, and only the second is a dead letter"

	| entry |
	entry := SoilQueueTestRepeatingEntry new.
	self assert: (entry isReadyToRunIn: nil)
]

{ #category : #tests }
SoilQueueDeadLetterTest >> testAnEntryBehindADeadLetterStillGetsItsTurn [
	"the parked one must not take the queue down with it"

	| gone good |
	gone := self put: (SoilQueueTestUnreachableEntry on: 'gone').
	good := self put: (SoilQueueTestRepeatingEntry on: SoilQueueTestTarget new).
	self workOffEverything.

	self assert: (self stateOf: gone) equals: nil.
	self assert: (self stateOf: good) equals: nil.
	self assert: self deadLetteredKeys equals: { gone -> #deadLetter }
]

{ #category : #tests }
SoilQueueDeadLetterTest >> testAnEntryThatOnlyFailsAtItsWorkIsNotADeadLetter [
	"failing at the work is a result and ends the entry the ordinary way. Two places for
	the same fact would be one too many"

	| key |
	key := self put: (SoilQueueTestRepeatingEntry on: SoilQueueTestTarget new).
	self workOffEverything.

	self assert: (self stateOf: key) equals: nil.
	self assert: self deadLetteredKeys equals: #(  )
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> workOffEverything [
	"what a restarted queue does, in the order it does it: the dispatcher gives orphaned
	claims back first, and only then is there anything for a worker to take. Driven
	straight through rather than forked -- a test that waits for a process cannot say what
	happened in it"

	| queue |
	queue := self queue.
	queue recoverOrphanedClaims.
	(SoilQueueWorker on: queue) run.
	^ queue
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> workOneUnit [
	"exactly one entry, so a test can look in between"

	^ (SoilQueueWorker on: self queue) runOnce
]
