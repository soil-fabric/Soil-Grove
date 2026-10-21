"
What happens to an entry the queue cannot work on at all.

Such an entry keeps coming back: its step fails around its work -- a target that cannot
be read -- so it is given back with a wait, the way an orphan is, and parked when its lane
allows no more. Dead lettering is reserved for that and kept apart from failing *at* the
work, which is a result and ends the entry the ordinary way. The two look alike from the
outside -- both leave the ordering -- and what separates them is where the entry ends up:
a dead letter is parked and can still be looked at, a finished entry is done with.

On a lane that lets an entry come back once, and without a wait, so that a test can drive
an entry to its dead letter straight through.

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
SoilQueueDeadLetterTest >> deadLetters [
	"each parked entry as its id and its state. By id, not by key: an entry that is given
	back first waits, and its key moves with the time it waits for"

	| txn letters |
	txn := soil newTransaction.
	letters := OrderedCollection new.
	^ [ (self workspaceIn: txn)
		deadLettersDo: [ :key :entry | letters add: entry id -> entry state ].
	  letters asArray ]
		ensure: [ txn abort ]
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> descriptionIn: aTransaction [

	^ (soil residentRegistryIn: aTransaction) descriptionNamed: #work
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> idOf: aKey [
	"the eight bytes that tell an entry apart, in the key it was put in under: the due time
	comes first, then the id"

	^ (aKey asByteArrayOfSize: 24) copyFrom: 9 to: 16
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
	  key := (self workspaceIn: txn) add: anEntry.
	  txn commit.
	  key ]
		ensure: [ txn isAborted ifFalse: [ txn abort ] ]
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> queue [

	| txn |
	txn := soil newTransaction.
	^ [ ((self descriptionIn: txn) newInstanceIn: txn)
		configureFrom: (self descriptionIn: txn) in: txn;
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
	soil addResidentDescription: ((SoilQueueDescription
		named: #work
		timeOrderedWithBackend: SoilSkipList
		keySize: 24)
		orphanedRetryLimit: 1;
		backoffBase: 0 seconds;
		yourself)
]

{ #category : #helpers }
SoilQueueDeadLetterTest >> stateOf: aKey [
	"nil when the entry put in under aKey has left the ordering. Found by its id, since its
	key moves when it is given back"

	| id txn |
	id := self idOf: aKey.
	txn := soil newTransaction.
	^ [ | found |
	  (self workspaceIn: txn) keysAndEntriesDo: [ :key :entry |
		entry id = id ifTrue: [ found := entry state ] ].
	  found ]
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
	self assert: self deadLetters equals: { (self idOf: key) -> #deadLetter }
]

{ #category : #tests }
SoilQueueDeadLetterTest >> testAnEntryThatCannotBeWorkedOnComesBackBeforeItIsParked [
	"what keeps it from its work may be gone a moment later, so it is given back first, as
	often as its lane allows -- here once"

	| key |
	key := self put: (SoilQueueTestUnreachableEntry on: 'gone').
	self workOneUnit.
	self assert: (self stateOf: key) equals: #pending.
	self assert: self deadLetters isEmpty.

	self workOneUnit.
	self assert: (self stateOf: key) equals: nil.
	self assert: self deadLetters equals: { (self idOf: key) -> #deadLetter }
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
	self assert: self deadLetters equals: { (self idOf: gone) -> #deadLetter }
]

{ #category : #tests }
SoilQueueDeadLetterTest >> testAnEntryThatOnlyFailsAtItsWorkIsNotADeadLetter [
	"failing at the work is a result and ends the entry the ordinary way. Two places for
	the same fact would be one too many"

	| key |
	key := self put: (SoilQueueTestBrokenEntry on: SoilQueueTestTarget new).
	self workOffEverything.

	self assert: (self stateOf: key) equals: nil.
	self assert: self deadLetters isEmpty
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

{ #category : #helpers }
SoilQueueDeadLetterTest >> workspaceIn: aTransaction [
	"where the entries are: the workspace the description holds"

	^ (self descriptionIn: aTransaction) workspace
]
